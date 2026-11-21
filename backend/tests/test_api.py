from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.core.errors import ApiError, register_error_handlers
from app.main import app

client = TestClient(app)


def test_health_ok() -> None:
    resp = client.get("/v1/health")
    assert resp.status_code == 200
    assert resp.json() == {"status": "ok"}


def test_beneficiaries_known_asha() -> None:
    resp = client.get("/v1/beneficiaries", params={"asha_id": "asha_001"})
    assert resp.status_code == 200
    data = resp.json()
    assert len(data) > 0
    assert all("id" in item and "label" in item for item in data)


def test_beneficiaries_unknown_asha_empty() -> None:
    resp = client.get("/v1/beneficiaries", params={"asha_id": "unknown_asha"})
    assert resp.status_code == 200
    assert resp.json() == []


def test_api_error_envelope() -> None:
    test_app = FastAPI()
    register_error_handlers(test_app)

    @test_app.get("/boom")
    def boom() -> None:
        raise ApiError("STT_FAILED", "Friendly failure message", 502)

    resp = TestClient(test_app).get("/boom")
    assert resp.status_code == 502
    assert resp.json() == {
        "error": {"code": "STT_FAILED", "message": "Friendly failure message"}
    }
