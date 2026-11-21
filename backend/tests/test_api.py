from fastapi.testclient import TestClient

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
