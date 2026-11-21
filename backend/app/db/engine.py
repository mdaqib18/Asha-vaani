"""SQLAlchemy engine, URL normalization, and Alembic migration runner."""

from __future__ import annotations

from pathlib import Path

from alembic import command
from alembic.config import Config
from sqlalchemy import Engine, create_engine, event
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy.pool import StaticPool

_BACKEND_DIR = Path(__file__).resolve().parent.parent.parent


def normalize_database_url(database_url: str) -> str:
    """Resolve relative SQLite paths against backend root while keeping Postgres URLs intact."""
    if database_url in (":memory:", "sqlite:///:memory:"):
        return "sqlite:///:memory:"
    if database_url.startswith("sqlite:///"):
        raw_path = database_url[len("sqlite:///") :]
        path = Path(raw_path)
        if not path.is_absolute():
            path = (_BACKEND_DIR / path).resolve()
        path.parent.mkdir(parents=True, exist_ok=True)
        return f"sqlite:///{path.as_posix()}"
    return database_url


def create_db_engine(database_url: str) -> Engine:
    """Create a SQLAlchemy Engine with SQLite foreign-key enforcement."""
    normalized = normalize_database_url(database_url)
    connect_args = {"check_same_thread": False} if normalized.startswith("sqlite") else {}
    kwargs: dict = {"future": True, "connect_args": connect_args}
    if normalized == "sqlite:///:memory:":
        kwargs["poolclass"] = StaticPool
    engine = create_engine(normalized, **kwargs)

    if normalized.startswith("sqlite"):

        @event.listens_for(engine, "connect")
        def _enable_sqlite_fk(dbapi_connection, _connection_record) -> None:
            cursor = dbapi_connection.cursor()
            cursor.execute("PRAGMA foreign_keys=ON")
            cursor.close()

    return engine


def make_session_factory(engine: Engine) -> sessionmaker[Session]:
    """Return a sessionmaker configured for V2 repositories."""
    return sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)


def build_alembic_config(database_url: str | None = None) -> Config:
    """Construct an Alembic Config anchored cleanly to backend/alembic."""
    ini_path = _BACKEND_DIR / "alembic.ini"
    cfg = Config(str(ini_path))
    cfg.set_main_option("script_location", str(_BACKEND_DIR / "alembic"))
    if database_url is not None:
        cfg.set_main_option("sqlalchemy.url", normalize_database_url(database_url))
    return cfg


def run_alembic_migrations(database_url: str, revision: str = "head") -> None:
    """Upgrade the target database to the given Alembic revision."""
    cfg = build_alembic_config(database_url)
    command.upgrade(cfg, revision)
