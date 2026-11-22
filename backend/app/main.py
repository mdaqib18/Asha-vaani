from contextlib import asynccontextmanager
import logging

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from sqlalchemy import func, select

from app.api.routes import router
from app.core.errors import ApiError, register_error_handlers
from app.core.security import PiiRedactingFilter, RateLimiter, verify_session_token
from app.core.settings import get_settings
from app.db.demo_seed import seed_demo_data
from app.db.engine import ensure_schema_ready, make_session_factory
from app.db.models import Beneficiary
from app.db.repository import V2Repository
from app.db.store import VisitStore

_UNAUTHENTICATED_PATHS = frozenset({"/v1/health", "/v1/auth/login", "/docs", "/openapi.json"})
_rate_limiter = RateLimiter()


def get_rate_limiter() -> RateLimiter:
    """Return global per-worker rate limiter instance."""
    return _rate_limiter


def _attach_log_redaction() -> None:
    for logger_name in ("app", "uvicorn", "uvicorn.access", "uvicorn.error"):
        logger = logging.getLogger(logger_name)
        if not any(isinstance(f, PiiRedactingFilter) for f in logger.filters):
            logger.addFilter(PiiRedactingFilter())


_attach_log_redaction()


@asynccontextmanager
async def lifespan(app_instance: FastAPI):
    """Run startup schema migrations and optional labeled demo data seeding."""
    _attach_log_redaction()
    settings_provider = app_instance.dependency_overrides.get(get_settings, get_settings)
    settings = settings_provider()

    VisitStore(settings.DATABASE_URL).close()
    engine = ensure_schema_ready(settings.DATABASE_URL)
    try:
        session_factory = make_session_factory(engine)
        if settings.SEED_DEMO_DATA:
            with session_factory() as db:
                beneficiary_count = db.scalar(select(func.count()).select_from(Beneficiary)) or 0
            if beneficiary_count == 0:
                repo = V2Repository(session_factory)
                seed_demo_data(repo)
    finally:
        engine.dispose()

    yield


app = FastAPI(title="Asha Vaani", lifespan=lifespan)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.middleware("http")
async def security_middleware(request: Request, call_next):
    settings_provider = app.dependency_overrides.get(get_settings, get_settings)
    settings = settings_provider()

    auth_header = request.headers.get("authorization", "")
    worker_sub: str | None = None
    if auth_header.lower().startswith("bearer "):
        token = auth_header.split(" ", 1)[1].strip()
        try:
            claims = verify_session_token(token, secret=settings.SESSION_SECRET)
            worker_sub = str(claims.get("sub", "")) or None
        except ApiError as exc:
            return JSONResponse(
                status_code=exc.http_status,
                content={"error": {"code": exc.code, "message": exc.message}},
            )
    elif settings.REQUIRE_AUTH and request.url.path not in _UNAUTHENTICATED_PATHS:
        return JSONResponse(
            status_code=401,
            content={
                "error": {
                    "code": "AUTH_REQUIRED",
                    "message": "Authentication required.",
                }
            },
        )

    rate_key = (
        worker_sub
        or request.query_params.get("asha_id")
        or request.headers.get("x-worker-id")
        or (request.client.host if request.client else "anonymous")
    )
    if not _rate_limiter.check_rate_limit(rate_key, settings.RATE_LIMIT_PER_MINUTE):
        return JSONResponse(
            status_code=429,
            content={
                "error": {
                    "code": "RATE_LIMITED",
                    "message": "Too many requests. Please retry after a minute.",
                }
            },
        )

    return await call_next(request)


register_error_handlers(app)
app.include_router(router)
