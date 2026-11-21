from __future__ import annotations

import logging
from pathlib import Path
from typing import Iterator

import pytest
from fastapi.testclient import TestClient

from app.core.security import PiiRedactingFilter, issue_session_token, verify_session_token
from app.core.settings import Settings, get_settings
from app.core.errors import ApiError
from app.db.repository import get_v2_repository
from app.db.store import VisitStore, get_store
from app.main import app, get_rate_limiter


@pytest.fixture
def security_client(tmp_path: Path) -> Iterator[TestClient]:
    db_url = f"sqlite:///{(tmp_path / 'sec.db').as_posix()}"
    store = VisitStore(db_url)
    get_v2_repository(store)
    get_rate_limiter().reset()
    settings = Settings(
        GNANI_API_KEY="test-key",
        LLM_API_KEY="test-key",
        DATABASE_URL=db_url,
        SESSION_SECRET="unit-test-secret",
        SESSION_TTL_SECONDS=3600,
        RATE_LIMIT_PER_MINUTE=120,
        REQUIRE_AUTH=True,
    )
    app.dependency_overrides[get_store] = lambda: store
    app.dependency_overrides[get_settings] = lambda: settings
    try:
        with TestClient(app) as client:
            yield client
    finally:
        app.dependency_overrides.clear()
        get_rate_limiter().reset()
        store.close()


def test_signed_token_issue_verify_tamper_and_expiry() -> None:
    token, expires_at = issue_session_token(
        "asha_001",
        secret="top-secret",
        ttl_seconds=120,
        now=1_000_000,
    )
    assert expires_at
    claims = verify_session_token(token, secret="top-secret", now=1_000_050)
    assert claims["sub"] == "asha_001"

    tampered = token[:-1] + ("A" if token[-1] != "A" else "B")
    with pytest.raises(ApiError) as exc_tamper:
        verify_session_token(tampered, secret="top-secret", now=1_000_050)
    assert exc_tamper.value.code == "TOKEN_INVALID"
    assert exc_tamper.value.http_status == 401

    with pytest.raises(ApiError) as exc_exp:
        verify_session_token(token, secret="top-secret", now=1_000_200)
    assert exc_exp.value.code == "TOKEN_EXPIRED"
    assert exc_exp.value.http_status == 401


def test_login_issues_signed_token_and_require_auth_enforces_bearer(
    security_client: TestClient,
) -> None:
    unauth = security_client.get("/v1/stats/summary")
    assert unauth.status_code == 401
    assert unauth.json()["error"]["code"] == "AUTH_REQUIRED"

    bad = security_client.get(
        "/v1/stats/summary",
        headers={"Authorization": "Bearer invalid.token.sig"},
    )
    assert bad.status_code == 401
    assert bad.json()["error"]["code"] == "TOKEN_INVALID"

    login_res = security_client.post(
        "/v1/auth/login",
        json={"worker_code": "asha_001", "pin": "1234"},
    )
    assert login_res.status_code == 200
    body = login_res.json()
    assert body["token"]
    assert body["expires_at"]

    authed = security_client.get(
        "/v1/stats/summary",
        headers={"Authorization": f"Bearer {body['token']}"},
    )
    assert authed.status_code == 200


def test_per_worker_rate_limiter_returns_429(tmp_path: Path) -> None:
    db_url = f"sqlite:///{(tmp_path / 'rl.db').as_posix()}"
    store = VisitStore(db_url)
    get_rate_limiter().reset()
    settings = Settings(
        GNANI_API_KEY="k",
        LLM_API_KEY="k",
        DATABASE_URL=db_url,
        RATE_LIMIT_PER_MINUTE=2,
        REQUIRE_AUTH=False,
    )
    app.dependency_overrides[get_store] = lambda: store
    app.dependency_overrides[get_settings] = lambda: settings
    try:
        with TestClient(app) as client:
            r1 = client.get("/v1/health", headers={"x-worker-id": "worker_a"})
            r2 = client.get("/v1/health", headers={"x-worker-id": "worker_a"})
            r3 = client.get("/v1/health", headers={"x-worker-id": "worker_a"})
            other = client.get("/v1/health", headers={"x-worker-id": "worker_b"})

            assert r1.status_code == 200
            assert r2.status_code == 200
            assert r3.status_code == 429
            assert r3.json()["error"]["code"] == "RATE_LIMITED"
            assert other.status_code == 200
    finally:
        app.dependency_overrides.clear()
        get_rate_limiter().reset()
        store.close()


def test_pii_redacting_log_filter() -> None:
    filt = PiiRedactingFilter()
    rec = logging.LogRecord(
        name="app.test",
        level=logging.INFO,
        pathname=__file__,
        lineno=1,
        msg='worker=%s auth=Bearer secretToken123 phone=9876543210 call 9123456789 "transcript":"Bacche ka wazan" full_name=Sunita',
        args=("asha_001",),
        exc_info=None,
    )
    assert filt.filter(rec) is True
    rendered = rec.getMessage()
    assert "secretToken123" not in rendered
    assert "9876543210" not in rendered
    assert "9123456789" not in rendered
    assert "Bacche ka wazan" not in rendered
    assert "Sunita" not in rendered
    assert "[REDACTED]" in rendered
    assert "[PHONE_REDACTED]" in rendered


def test_mobile_source_contains_no_api_secrets() -> None:
    repo_root = Path(__file__).resolve().parents[2]
    mobile_lib = repo_root / "mobile" / "lib"
    assert mobile_lib.exists()

    forbidden_substrings = (
        "GNANI_API_KEY",
        "LLM_API_KEY",
        "api.vachana.ai",
        "generativelanguage.googleapis.com",
        "AIza",
    )
    for dart_file in mobile_lib.rglob("*.dart"):
        content = dart_file.read_text(encoding="utf-8")
        for needle in forbidden_substrings:
            assert needle not in content, f"Forbidden secret/endpoint {needle!r} in {dart_file}"
