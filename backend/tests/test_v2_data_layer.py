from __future__ import annotations

from datetime import date, datetime, timedelta, timezone
from pathlib import Path

import pytest
from alembic import command
from sqlalchemy import inspect

from app.db.engine import (
    build_alembic_config,
    create_db_engine,
    make_session_factory,
    run_alembic_migrations,
)
from app.db.models import Beneficiary
from app.db.repository import V2Repository, VisitImmutableError
from app.db.store import StoredSession, VisitStore
from app.services.due_engine import (
    compute_edd,
    compute_next_due_at,
    derive_risk_level,
)
from app.services.duplicate_detector import (
    DuplicateCandidateInput,
    find_duplicate_candidates,
    name_similarity,
    normalize_name,
)

EXPECTED_V2_TABLES = {
    "workers",
    "areas",
    "households",
    "beneficiaries",
    "pregnancies",
    "visit_types",
    "visits",
    "visit_measurements",
    "visit_amendments",
    "followups",
    "audio_assets",
    "consents",
    "sync_queue",
    "audit_log",
}

EXPECTED_INDEXES = {
    "ix_beneficiaries_worker_status_due",
    "uq_beneficiaries_worker_local_code",
    "ix_visits_beneficiary_visited",
    "ix_visits_worker_visited",
    "ix_visit_measurements_ben_key_at",
}


def test_alembic_upgrade_downgrade_and_schema(tmp_path: Path) -> None:
    db_path = tmp_path / "v2_schema.db"
    db_url = f"sqlite:///{db_path.as_posix()}"

    run_alembic_migrations(db_url, "head")
    engine = create_db_engine(db_url)
    try:
        inspector = inspect(engine)
        tables = set(inspector.get_table_names())
        assert EXPECTED_V2_TABLES.issubset(tables)

        found_indexes: set[str] = set()
        for table in ("beneficiaries", "visits", "visit_measurements"):
            for idx in inspector.get_indexes(table):
                if idx["name"]:
                    found_indexes.add(idx["name"])
        assert EXPECTED_INDEXES.issubset(found_indexes)
    finally:
        engine.dispose()

    cfg = build_alembic_config(db_url)
    command.downgrade(cfg, "base")
    engine2 = create_db_engine(db_url)
    try:
        tables_after_down = set(inspect(engine2).get_table_names())
        assert EXPECTED_V2_TABLES.isdisjoint(tables_after_down)
    finally:
        engine2.dispose()

    command.upgrade(cfg, "head")
    engine3 = create_db_engine(db_url)
    try:
        assert EXPECTED_V2_TABLES.issubset(set(inspect(engine3).get_table_names()))
    finally:
        engine3.dispose()


def test_alembic_upgrade_preserves_existing_v1_tables(tmp_path: Path) -> None:
    db_path = tmp_path / "legacy_v1.db"
    db_url = f"sqlite:///{db_path.as_posix()}"

    v1_store = VisitStore(db_url)
    v1_store.create_or_update_session(
        StoredSession(session_id="v1-sess-1", asha_id="asha_001", status="saved")
    )
    v1_store.save_sync_result("client-1", {"client_id": "client-1", "ok": True})
    v1_store.close()

    run_alembic_migrations(db_url, "head")

    v1_store_after = VisitStore(db_url)
    try:
        restored = v1_store_after.get_session("v1-sess-1")
        assert restored is not None
        assert restored.status == "saved"
        assert v1_store_after.get_sync_result("client-1") == {"client_id": "client-1", "ok": True}
    finally:
        v1_store_after.close()

    engine = create_db_engine(db_url)
    try:
        assert EXPECTED_V2_TABLES.issubset(set(inspect(engine).get_table_names()))
    finally:
        engine.dispose()


def test_due_engine_schedules_and_risk_levels() -> None:
    dob = date(2026, 11, 1)
    assert compute_next_due_at("newborn", dob=dob, today=dob) == date(2026, 11, 4)
    assert compute_next_due_at("newborn", dob=dob, visited_at=date(2026, 11, 4)) == date(
        2026, 11, 8
    )
    assert compute_next_due_at("newborn", dob=dob, visited_at=date(2026, 11, 29)) == date(
        2026, 12, 13
    )
    assert compute_next_due_at("newborn", dob=dob, visited_at=date(2026, 12, 13)) is None

    lmp = date(2026, 1, 1)
    assert compute_edd(lmp) == date(2026, 10, 8)
    assert compute_next_due_at(
        "pregnant_woman",
        visited_at=date(2026, 5, 1),
        lmp_date=lmp,
    ) == date(2026, 5, 31)

    assert compute_next_due_at("pnc_mother", dob=dob, visited_at=date(2026, 11, 8)) == date(
        2026, 11, 15
    )

    assert derive_risk_level([]) == "none"
    assert derive_risk_level(["mild_note"]) == "watch"
    assert derive_risk_level(["low_birth_weight"]) == "high"
    assert derive_risk_level([], referral_suggested=True) == "high"


def test_duplicate_detector_normalization_and_matching() -> None:
    assert normalize_name("Smt. Suneeta Devi") == normalize_name("Sunita")
    assert name_similarity("Radha Kumari", "Kumari Radha") >= 0.99

    existing = [
        DuplicateCandidateInput(
            id="b1",
            local_code="1042",
            full_name="Smt. Suneeta Devi",
            worker_id="asha_001",
            area_id="area_asha_001",
            dob="2000-05-10",
            phone_enc="+91 98765-43210",
        ),
        DuplicateCandidateInput(
            id="b2",
            local_code="1043",
            full_name="Kavita Sharma",
            worker_id="asha_001",
            area_id="area_asha_002",
            dob="2000-05-10",
            phone_enc="9999999999",
        ),
        DuplicateCandidateInput(
            id="b3",
            local_code="1044",
            full_name="Sunita",
            worker_id="asha_001",
            area_id="area_asha_001",
            dob="2000-05-10",
            status="closed",
            deleted_at="2026-11-01T00:00:00Z",
        ),
    ]

    matches = find_duplicate_candidates(
        DuplicateCandidateInput(
            id="new-1",
            local_code="1099",
            full_name="Sunita",
            worker_id="asha_001",
            area_id="area_asha_001",
            dob="2000-08-15",
            phone_enc="9876543210",
        ),
        existing,
    )
    assert len(matches) == 1
    assert matches[0].beneficiary_id == "b1"
    assert "similar_name" in matches[0].reasons
    assert "same_phone" in matches[0].reasons

    # Newborn sharing mother's household phone must not false-match mother
    baby_matches = find_duplicate_candidates(
        DuplicateCandidateInput(
            id="new-baby",
            local_code="1100",
            full_name="Baby of Sunita",
            worker_id="asha_001",
            area_id="area_asha_001",
            dob="2026-11-18",
            phone_enc="9876543210",
        ),
        existing,
    )
    assert baby_matches == []


def test_repository_confirm_immutability_amend_lww_and_retention(tmp_path: Path) -> None:
    db_path = tmp_path / "repo.db"
    db_url = f"sqlite:///{db_path.as_posix()}"
    run_alembic_migrations(db_url, "head")
    engine = create_db_engine(db_url)
    repo = V2Repository(make_session_factory(engine))

    try:
        repo.seed_defaults()
        reserved = repo.reserve_local_code("asha_001")
        assert reserved == "1058"

        baby = repo.create_beneficiary(
            worker_id="asha_001",
            area_id="area_asha_001",
            full_name="Baby of Geeta",
            beneficiary_type="newborn",
            dob="2026-11-15",
            phone_enc="9123456789",
        )
        assert baby.consent_id is not None
        assert baby.next_due_at is not None

        mother = repo.create_beneficiary(
            worker_id="asha_001",
            area_id="area_asha_001",
            full_name="Geeta",
            beneficiary_type="pregnant_woman",
            lmp_date="2026-03-01",
        )
        assert mother.local_code != baby.local_code

        draft = repo.create_draft_visit(
            beneficiary_id=baby.id,
            worker_id="asha_001",
            visit_type_code="newborn_home_visit",
            visited_at="2026-11-18",
            payload={"baby_weight_kg": {"value": 2.2}, "temperature_c": 37.9},
            risk_flags=["low_birth_weight", "elevated_temperature"],
            referral_suggested=True,
        )
        confirmed = repo.confirm_visit(draft.id)
        assert confirmed.status == "confirmed"
        assert confirmed.confirmed_at is not None
        assert confirmed.next_due_at == "2026-11-22"

        updated_baby = repo.get_beneficiary(baby.id)
        assert updated_baby is not None
        assert updated_baby.last_visit_at == "2026-11-18"
        assert updated_baby.next_due_at == "2026-11-22"
        assert updated_baby.risk_level == "high"
        assert updated_baby.version == 2

        measurements = repo.get_visit_measurements(baby.id)
        keys_vals = {m.key: m.value_num for m in measurements}
        assert keys_vals == {"baby_weight_kg": 2.2, "temperature_c": 37.9}

        with pytest.raises(VisitImmutableError):
            repo.confirm_visit(draft.id)

        amended, amendment = repo.amend_visit(
            draft.id,
            changed_by="asha_001",
            changes={"baby_weight_kg": 2.7, "temperature_c": 36.8},
            reason="Scale zeroed and reweighed",
            risk_flags=[],
            referral_suggested=False,
        )
        assert amended.status == "amended"
        assert amendment.reason == "Scale zeroed and reweighed"

        amended_measurements = {
            m.key: m.value_num for m in repo.get_visit_measurements(baby.id)
        }
        assert amended_measurements == {"baby_weight_kg": 2.7, "temperature_c": 36.8}

        refreshed_baby = repo.get_beneficiary(baby.id)
        assert refreshed_baby is not None
        assert refreshed_baby.risk_level == "none"

        # LWW rejects older update and applies newer update
        stale_ts = (datetime.now(timezone.utc) - timedelta(hours=1)).isoformat()
        _, applied_stale = repo.upsert_beneficiary_lww(
            beneficiary_id=baby.id,
            local_code=baby.local_code,
            worker_id="asha_001",
            full_name="Stale Name",
            updated_at=stale_ts,
            version=1,
        )
        assert applied_stale is False

        newer_ts = (datetime.now(timezone.utc) + timedelta(minutes=5)).isoformat()
        newer_row, applied_newer = repo.upsert_beneficiary_lww(
            beneficiary_id=baby.id,
            local_code=baby.local_code,
            worker_id="asha_001",
            full_name="Baby of Geeta Devi",
            updated_at=newer_ts,
            version=10,
        )
        assert applied_newer is True
        assert newer_row.full_name == "Baby of Geeta Devi"

        # Soft delete hides from active list without dropping DB row
        repo.soft_delete_beneficiary(baby.id, actor_id="asha_001")
        active_ids = {b.id for b in repo.list_beneficiaries("asha_001")}
        assert baby.id not in active_ids
        all_ids = {b.id for b in repo.list_beneficiaries("asha_001", include_deleted=True)}
        assert baby.id in all_ids

        # Audio retention deletes uploaded+confirmed and expired assets
        wav_uploaded = tmp_path / "uploaded.wav"
        wav_uploaded.write_bytes(b"RIFFdata")
        repo.record_audio_asset(
            asset_id="aud-1",
            visit_id=draft.id,
            path=str(wav_uploaded),
            state="uploaded",
        )
        wav_expired = tmp_path / "expired.wav"
        wav_expired.write_bytes(b"RIFFold")
        repo.record_audio_asset(
            asset_id="aud-2",
            visit_id=None,
            path=str(wav_expired),
            state="local",
            retention_days=7,
            created_at=datetime.now(timezone.utc) - timedelta(days=10),
        )
        purged = repo.purge_expired_audio()
        assert set(purged) == {"aud-1", "aud-2"}
        assert not wav_uploaded.exists()
        assert not wav_expired.exists()

        audits = repo.get_audit_logs()
        actions = {a.action for a in audits}
        assert {
            "beneficiary_created",
            "visit_confirmed",
            "visit_amended",
            "beneficiary_soft_deleted",
            "audio_deleted",
        }.issubset(actions)
    finally:
        engine.dispose()
