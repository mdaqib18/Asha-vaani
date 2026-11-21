"""Idempotent labeled demo data seeder for SPEC_V2 §6 Statistical Insights."""

from __future__ import annotations

import argparse
import sys
from datetime import date, datetime, time, timedelta, timezone
from pathlib import Path

from sqlalchemy import delete, select

BACKEND_ROOT = Path(__file__).resolve().parents[1]
if str(BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(BACKEND_ROOT))

from app.core.settings import get_settings
from app.db.engine import create_db_engine, make_session_factory
from app.db.models import (
    AuditLogEntry,
    Base,
    Beneficiary,
    Consent,
    FollowupRecord,
    Pregnancy,
    Visit,
    VisitMeasurement,
)
from app.db.repository import V2Repository


DEMO_PREFIX = "demo_seed_"


def _iso_at(day: date, hour: int, minute: int, second: int = 0) -> str:
    return datetime.combine(day, time(hour, minute, second), tzinfo=timezone.utc).isoformat()


def clear_demo_data(repo: V2Repository, *, worker_id: str = "asha_001") -> int:
    """Remove previously seeded `demo_seed_*` rows for the worker."""
    removed = 0
    with repo._session_factory() as db, db.begin():
        demo_visit_ids = list(
            db.scalars(
                select(Visit.id).where(
                    Visit.worker_id == worker_id,
                    Visit.id.like(f"{DEMO_PREFIX}%"),
                )
            ).all()
        )
        demo_ben_ids = list(
            db.scalars(
                select(Beneficiary.id).where(
                    Beneficiary.worker_id == worker_id,
                    Beneficiary.id.like(f"{DEMO_PREFIX}%"),
                )
            ).all()
        )
        if demo_visit_ids:
            db.execute(delete(FollowupRecord).where(FollowupRecord.visit_id.in_(demo_visit_ids)))
            db.execute(delete(VisitMeasurement).where(VisitMeasurement.visit_id.in_(demo_visit_ids)))
            res = db.execute(delete(Visit).where(Visit.id.in_(demo_visit_ids)))
            removed += res.rowcount or 0
        if demo_ben_ids:
            db.execute(delete(Consent).where(Consent.beneficiary_id.in_(demo_ben_ids)))
            db.execute(delete(Pregnancy).where(Pregnancy.beneficiary_id.in_(demo_ben_ids)))
            res = db.execute(delete(Beneficiary).where(Beneficiary.id.in_(demo_ben_ids)))
            removed += res.rowcount or 0
        db.execute(
            delete(AuditLogEntry).where(
                AuditLogEntry.actor_id == worker_id,
                AuditLogEntry.entity_id.like(f"{DEMO_PREFIX}%"),
            )
        )
    return removed


def seed_demo_data(
    repo: V2Repository,
    *,
    worker_id: str = "asha_001",
    today: date | None = None,
) -> dict[str, int]:
    """Seed labeled 14-day multi-purpose synthetic demo visits (idempotent)."""
    ref_today = today or datetime.now(timezone.utc).date()
    repo.seed_defaults()

    ben_specs = [
        {
            "id": f"{DEMO_PREFIX}ben_1",
            "local_code": "D-101",
            "full_name": "Demo Baby Aarav",
            "beneficiary_type": "newborn",
            "sex": "male",
            "dob": (ref_today - timedelta(days=9)).isoformat(),
            "area_note": "Ward 2 Rampur",
            "lmp_date": None,
        },
        {
            "id": f"{DEMO_PREFIX}ben_2",
            "local_code": "D-102",
            "full_name": "Demo Kavita Devi",
            "beneficiary_type": "pregnant_woman",
            "sex": "female",
            "dob": "1998-04-12",
            "area_note": "Ward 2 Rampur",
            "lmp_date": (ref_today - timedelta(days=190)).isoformat(),
        },
        {
            "id": f"{DEMO_PREFIX}ben_3",
            "local_code": "D-103",
            "full_name": "Demo Rohan Kumar",
            "beneficiary_type": "child_u5",
            "sex": "male",
            "dob": (ref_today - timedelta(days=760)).isoformat(),
            "area_note": "Ward 3 Devpur",
            "lmp_date": None,
        },
        {
            "id": f"{DEMO_PREFIX}ben_4",
            "local_code": "D-104",
            "full_name": "Demo Meera Bai",
            "beneficiary_type": "adult",
            "sex": "female",
            "dob": "1972-09-20",
            "area_note": "Ward 3 Devpur",
            "lmp_date": None,
        },
        {
            "id": f"{DEMO_PREFIX}ben_5",
            "local_code": "D-105",
            "full_name": "Demo Baby Ananya",
            "beneficiary_type": "newborn",
            "sex": "female",
            "dob": (ref_today - timedelta(days=21)).isoformat(),
            "area_note": "Ward 1 Kendra",
            "lmp_date": None,
        },
        {
            "id": f"{DEMO_PREFIX}ben_6",
            "local_code": "D-106",
            "full_name": "Demo Sita Verma",
            "beneficiary_type": "pregnant_woman",
            "sex": "female",
            "dob": "2000-02-18",
            "area_note": "Ward 1 Kendra",
            "lmp_date": (ref_today - timedelta(days=145)).isoformat(),
        },
    ]

    created_ben = 0
    for spec in ben_specs:
        if repo.get_beneficiary_by_id_or_code(spec["id"], worker_id=worker_id) is None:
            repo.create_beneficiary(
                beneficiary_id=spec["id"],
                local_code=spec["local_code"],
                worker_id=worker_id,
                full_name=spec["full_name"],
                beneficiary_type=spec["beneficiary_type"],
                sex=spec["sex"],
                dob=spec["dob"],
                area_note=spec["area_note"],
                lmp_date=spec["lmp_date"],
                device_id="demo_seeder",
            )
            created_ben += 1

    # Ensure due_today (>= 1) and overdue (>= 1) exist deterministically
    with repo._session_factory() as db, db.begin():
        b_today = db.get(Beneficiary, f"{DEMO_PREFIX}ben_5")
        if b_today is not None:
            b_today.next_due_at = ref_today.isoformat()
        b_overdue = db.get(Beneficiary, f"{DEMO_PREFIX}ben_6")
        if b_overdue is not None:
            b_overdue.next_due_at = (ref_today - timedelta(days=3)).isoformat()

    visit_specs = [
        # day_offset=0 (today)
        (1, f"{DEMO_PREFIX}ben_1", "newborn_home_visit", 0, "voice", 44, {"weight_kg": 2.25, "temperature_c": 36.2}, ["low_birth_weight", "hypothermia"], True, True),
        (2, f"{DEMO_PREFIX}ben_4", "ncd_screening", 0, "mixed", 38, {"bp_systolic": 132, "bp_diastolic": 84}, [], False, False),
        # last 7 days
        (3, f"{DEMO_PREFIX}ben_2", "anc_visit", 1, "voice", 52, {"bp_systolic": 148, "bp_diastolic": 96}, ["high_blood_pressure"], True, True),
        (4, f"{DEMO_PREFIX}ben_3", "general_illness", 2, "voice", 49, {"temperature_c": 38.4}, ["fever"], False, False),
        (5, f"{DEMO_PREFIX}ben_5", "newborn_home_visit", 4, "manual", 0, {"weight_kg": 3.1, "temperature_c": 36.8}, [], False, False),
        (6, f"{DEMO_PREFIX}ben_2", "anc_visit", 6, "voice", 58, {"bp_systolic": 136, "bp_diastolic": 88}, ["swelling"], False, True),
        # days 7..13 ago (30d window)
        (7, f"{DEMO_PREFIX}ben_1", "newborn_home_visit", 8, "voice", 61, {"weight_kg": 2.3, "temperature_c": 36.6}, ["low_birth_weight"], False, False),
        (8, f"{DEMO_PREFIX}ben_3", "general_illness", 11, "voice", 41, {"temperature_c": 37.9}, ["cough"], False, False),
        (9, f"{DEMO_PREFIX}ben_4", "ncd_screening", 13, "voice", 39, {"bp_systolic": 152, "bp_diastolic": 94}, ["high_blood_pressure"], True, False),
    ]

    created_visits = 0
    for idx, ben_id, purpose, days_ago, method, dur_secs, payload, flags, referral, has_fu in sorted(
        visit_specs,
        key=lambda spec: -spec[3],
    ):
        vid = f"{DEMO_PREFIX}visit_{idx}"
        cid = f"{DEMO_PREFIX}visit_{idx}"
        if repo.get_visit(vid) is not None:
            continue

        visit_day = ref_today - timedelta(days=days_ago)
        started_iso = _iso_at(visit_day, 10, 0, 0)
        confirmed_dt = datetime.combine(visit_day, time(10, 0, 0), tzinfo=timezone.utc) + timedelta(
            seconds=dur_secs
        )

        repo.create_draft_visit(
            visit_id=vid,
            client_id=cid,
            beneficiary_id=ben_id,
            worker_id=worker_id,
            visit_type_code=purpose,
            visited_at=visit_day.isoformat(),
            payload=payload,
            risk_flags=flags,
            referral_suggested=referral,
            input_method=method,
            started_at=started_iso,
        )
        repo.confirm_visit(
            vid,
            actor_id=worker_id,
            payload=payload,
            risk_flags=flags,
            referral_suggested=referral,
            device_id="demo_seeder",
        )
        # Preserve historical day + measured voice duration + keep due_today/overdue anchors accurate
        with repo._session_factory() as db, db.begin():
            row = db.get(Visit, vid)
            if row is not None:
                row.visited_at = visit_day.isoformat()
                row.confirmed_at = confirmed_dt.isoformat()
            if has_fu:
                db.add(
                    FollowupRecord(
                        id=f"{DEMO_PREFIX}fu_{idx}",
                        visit_id=vid,
                        question_text="Demo follow-up verification question",
                        target_fields="[]",
                        answer_text="Confirmed during demo recording",
                        created_at=confirmed_dt.isoformat(),
                    )
                )
        created_visits += 1

    # Re-apply due anchors on ben_5 & ben_6 after confirms so demo stats always show due_today >= 1 and overdue >= 1
    with repo._session_factory() as db, db.begin():
        b_today = db.get(Beneficiary, f"{DEMO_PREFIX}ben_5")
        if b_today is not None:
            b_today.next_due_at = ref_today.isoformat()
        b_overdue = db.get(Beneficiary, f"{DEMO_PREFIX}ben_6")
        if b_overdue is not None:
            b_overdue.next_due_at = (ref_today - timedelta(days=3)).isoformat()

    return {"beneficiaries_created": created_ben, "visits_created": created_visits}


def main() -> None:
    parser = argparse.ArgumentParser(description="Seed labeled V2 demo visits & stats data.")
    parser.add_argument("--worker-id", default="asha_001")
    parser.add_argument("--clear", action="store_true", help="Remove demo_seed_* rows instead.")
    args = parser.parse_args()

    settings = get_settings()
    engine = create_db_engine(settings.DATABASE_URL)
    Base.metadata.create_all(engine)
    repo = V2Repository(make_session_factory(engine))
    if args.clear:
        count = clear_demo_data(repo, worker_id=args.worker_id)
        print(f"Removed {count} demo_seed_* rows for {args.worker_id}.")
    else:
        res = seed_demo_data(repo, worker_id=args.worker_id)
        print(
            f"Demo seed complete for {args.worker_id}: "
            f"+{res['beneficiaries_created']} beneficiaries, +{res['visits_created']} visits."
        )


if __name__ == "__main__":
    main()
