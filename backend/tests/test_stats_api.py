from __future__ import annotations

from collections.abc import Iterator
from datetime import date, datetime, timezone
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from app.core.settings import Settings, get_settings
from app.db.repository import V2Repository, get_v2_repository
from app.db.store import StoredSession, VisitStore, get_store
from app.main import app
from app.schemas.newborn_visit import ExtractedField, FieldSource
from scripts.seed_demo_stats import clear_demo_data, seed_demo_data


@pytest.fixture
def stats_client(tmp_path: Path) -> Iterator[tuple[TestClient, V2Repository, VisitStore]]:
    db_url = f"sqlite:///{(tmp_path / 'stats.db').as_posix()}"
    store = VisitStore(db_url)
    repo = get_v2_repository(store)
    settings = Settings(
        GNANI_API_KEY="test-key",
        LLM_API_KEY="test-key",
        DATABASE_URL=db_url,
    )
    app.dependency_overrides[get_store] = lambda: store
    app.dependency_overrides[get_settings] = lambda: settings
    try:
        with TestClient(app) as client:
            yield client, repo, store
    finally:
        app.dependency_overrides.clear()
        store.close()


def test_stats_empty_state_and_period_validation(
    stats_client: tuple[TestClient, V2Repository, VisitStore],
) -> None:
    client, _, _ = stats_client
    res = client.get(
        "/v1/stats/summary",
        params={"period": "7d", "asha_id": "asha_empty", "today": "2026-11-22"},
    )
    assert res.status_code == 200
    body = res.json()
    assert body["visits_done"] == 0
    assert body["active_beneficiaries"] == 0
    assert body["coverage"] == 0.0
    assert body["avg_record_seconds"] is None
    assert body["voice_share"] is None
    assert body["followup_rate"] is None
    assert body["has_demo_data"] is False

    # Seeded default worker starts with 3 active starter beneficiaries and 0 visits.
    res_default = client.get(
        "/v1/stats/summary",
        params={"period": "7d", "asha_id": "asha_001", "today": "2026-11-22"},
    )
    assert res_default.status_code == 200
    assert res_default.json()["active_beneficiaries"] == 3
    assert res_default.json()["visits_done"] == 0

    bad = client.get("/v1/stats/summary", params={"period": "90d"})
    assert bad.status_code == 400
    assert bad.json()["error"]["code"] == "INVALID_PERIOD"

    assert len(client.get("/v1/stats/visits-timeseries", params={"period": "today"}).json()) == 1
    assert len(client.get("/v1/stats/visits-timeseries", params={"period": "7d"}).json()) == 7
    assert len(client.get("/v1/stats/visits-timeseries", params={"period": "30d"}).json()) == 30


def test_demo_seeder_idempotency_endpoints_and_clear(
    stats_client: tuple[TestClient, V2Repository, VisitStore],
) -> None:
    client, repo, _ = stats_client
    ref_today = date(2026, 11, 22)
    worker_id = "asha_demo_tester"

    first = seed_demo_data(repo, worker_id=worker_id, today=ref_today)
    assert first == {"beneficiaries_created": 6, "visits_created": 9}

    second = seed_demo_data(repo, worker_id=worker_id, today=ref_today)
    assert second == {"beneficiaries_created": 0, "visits_created": 0}

    summary_today = client.get(
        "/v1/stats/summary",
        params={"period": "today", "asha_id": worker_id, "today": "2026-11-22"},
    ).json()
    assert summary_today["visits_done"] == 2
    assert summary_today["referrals_suggested"] == 1
    assert summary_today["high_risk_open"] == 3
    assert summary_today["due_today"] >= 1
    assert summary_today["overdue"] >= 1
    assert summary_today["coverage"] == pytest.approx(5 / 6, abs=0.001)
    assert summary_today["avg_record_seconds"] == pytest.approx(44.0)
    assert summary_today["voice_share"] == pytest.approx(1.0)
    assert summary_today["followup_rate"] == pytest.approx(0.5)
    assert summary_today["has_demo_data"] is True

    summary_7d = client.get(
        "/v1/stats/summary",
        params={"period": "7d", "asha_id": worker_id, "today": "2026-11-22"},
    ).json()
    assert summary_7d["visits_done"] == 6
    assert summary_7d["referrals_suggested"] == 2
    assert summary_7d["voice_share"] == pytest.approx(5 / 6, abs=0.001)

    summary_30d = client.get(
        "/v1/stats/summary",
        params={"period": "30d", "asha_id": worker_id, "today": "2026-11-22"},
    ).json()
    assert summary_30d["visits_done"] == 9

    ts = client.get(
        "/v1/stats/visits-timeseries",
        params={"period": "7d", "asha_id": worker_id, "today": "2026-11-22"},
    ).json()
    assert len(ts) == 7
    assert sum(p["count"] for p in ts) == 6
    assert ts[-1]["date"] == "2026-11-22"
    assert ts[-1]["count"] == 2
    assert ts[-1]["high_risk_count"] == 1

    purposes = client.get(
        "/v1/stats/by-purpose",
        params={"period": "30d", "asha_id": worker_id, "today": "2026-11-22"},
    ).json()
    assert {item["key"] for item in purposes} == {
        "newborn_home_visit",
        "anc_visit",
        "general_illness",
        "ncd_screening",
    }
    assert purposes[0]["count"] >= purposes[-1]["count"]

    risks = client.get(
        "/v1/stats/risk-breakdown",
        params={"period": "30d", "asha_id": worker_id, "today": "2026-11-22"},
    ).json()
    top_keys = {item["key"] for item in risks[:3]}
    assert "low_birth_weight" in top_keys
    assert "high_blood_pressure" in top_keys

    due_list = client.get(
        "/v1/stats/due-list",
        params={"asha_id": worker_id, "today": "2026-11-22"},
    ).json()
    assert len(due_list) >= 2
    codes = [item["local_code"] for item in due_list]
    assert "D-106" in codes and "D-105" in codes
    assert codes.index("D-106") < codes.index("D-105")
    assert due_list[0]["days_overdue"] == 3

    removed = clear_demo_data(repo, worker_id=worker_id)
    assert removed == 15
    after_clear = client.get(
        "/v1/stats/summary",
        params={"period": "30d", "asha_id": worker_id, "today": "2026-11-22"},
    ).json()
    assert after_clear["visits_done"] == 0
    assert after_clear["has_demo_data"] is False


def test_legacy_visit_store_deduplication(
    stats_client: tuple[TestClient, V2Repository, VisitStore],
) -> None:
    client, repo, store = stats_client
    today = datetime.now(timezone.utc).date()
    repo.seed_defaults()
    ben = repo.create_beneficiary(
        beneficiary_id="real_ben_1",
        worker_id="asha_001",
        full_name="Sunita Devi",
        beneficiary_type="newborn",
    )
    repo.create_draft_visit(
        visit_id="v_shared",
        beneficiary_id=ben.id,
        worker_id="asha_001",
        visited_at=today.isoformat(),
        payload={"weight_kg": 3.0},
    )
    repo.confirm_visit("v_shared", actor_id="asha_001")

    shared_sess = StoredSession(
        session_id="v_shared",
        visit_id="v_shared",
        asha_id="asha_001",
        status="saved",
        updated_at="2026-11-22T09:00:00+00:00",
        created_at="2026-11-22T08:59:00+00:00",
    )
    shared_sess.record.beneficiary_id = ExtractedField(
        value=ben.local_code, confidence=1.0, source=FieldSource.selected
    )
    store.create_or_update_session(shared_sess)

    legacy_only = StoredSession(
        session_id="legacy_only_1",
        visit_id="legacy_only_1",
        asha_id="asha_001",
        status="saved",
        updated_at="2026-11-22T11:00:00+00:00",
        created_at="2026-11-22T10:59:00+00:00",
    )
    legacy_only.record.beneficiary_id = ExtractedField(
        value=ben.local_code, confidence=1.0, source=FieldSource.selected
    )
    store.create_or_update_session(legacy_only)

    summary = client.get(
        "/v1/stats/summary",
        params={"period": "today", "today": today.isoformat()},
    ).json()
    assert summary["visits_done"] == 2
    assert summary["has_demo_data"] is False
