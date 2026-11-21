"""Transaction-safe SQLAlchemy repository for V2 clinical data (SPEC_V2 §5)."""

from __future__ import annotations

import json
import uuid
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

from sqlalchemy import select
from sqlalchemy.orm import Session, sessionmaker

from app.core.settings import get_settings
from app.data.beneficiaries import SYNTHETIC_BENEFICIARIES, SYNTHETIC_WORKERS
from app.db.models import (
    Area,
    AudioAsset,
    AuditLogEntry,
    Beneficiary,
    Consent,
    Pregnancy,
    Visit,
    VisitAmendment,
    VisitMeasurement,
    Worker,
)
from app.services.due_engine import compute_edd, compute_next_due_at, derive_risk_level
from app.services.duplicate_detector import (
    DuplicateCandidateInput,
    DuplicateMatch,
    find_duplicate_candidates,
)
from app.services.measurements import extract_numeric_measurements


class VisitImmutableError(ValueError):
    """Raised when attempting to mutate an already confirmed or amended visit directly."""


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


def _utc_iso(dt: datetime | None = None) -> str:
    return (dt or _utc_now()).isoformat()


def _parse_date(raw: str | None) -> date | None:
    if not raw:
        return None
    try:
        return date.fromisoformat(raw[:10])
    except ValueError:
        return None


def _parse_iso_dt(raw: str | None) -> datetime | None:
    if not raw:
        return None
    try:
        normalized = raw.replace("Z", "+00:00")
        dt = datetime.fromisoformat(normalized)
        return dt if dt.tzinfo is not None else dt.replace(tzinfo=timezone.utc)
    except ValueError:
        return None


class V2Repository:
    """Repository providing atomic transactions for V2 entities, derived caches, and audits."""

    def __init__(self, session_factory: sessionmaker[Session]) -> None:
        self._session_factory = session_factory

    def _append_audit(
        self,
        db: Session,
        *,
        actor_id: str,
        action: str,
        entity: str,
        entity_id: str,
        device_id: str = "backend",
        at: str | None = None,
    ) -> None:
        db.add(
            AuditLogEntry(
                id=str(uuid.uuid4()),
                actor_id=actor_id,
                action=action,
                entity=entity,
                entity_id=entity_id,
                device_id=device_id,
                at=at or _utc_iso(),
            )
        )

    def seed_defaults(self) -> None:
        """Idempotently seed synthetic demo workers, areas, and starter beneficiaries."""
        now = _utc_iso()
        with self._session_factory() as db, db.begin():
            for code, worker in SYNTHETIC_WORKERS.items():
                area_id = f"area_{code}"
                if db.get(Area, area_id) is None:
                    db.add(Area(id=area_id, name=worker["area"], code=area_id))
                if db.get(Worker, worker["id"]) is None:
                    db.add(
                        Worker(
                            id=worker["id"],
                            worker_code=worker["worker_code"],
                            name=worker["name"],
                            language_pref="hi",
                            area_ids=json.dumps([area_id]),
                            pin_hash=worker["pin_hash"],
                            created_at=now,
                        )
                    )

            db.flush()

            for worker_id, rows in SYNTHETIC_BENEFICIARIES.items():
                area_id = f"area_{worker_id}"
                for item in rows:
                    ben_id = f"seed_{worker_id}_{item['id']}"
                    if db.get(Beneficiary, ben_id) is None:
                        db.add(
                            Beneficiary(
                                id=ben_id,
                                local_code=item["id"],
                                worker_id=worker_id,
                                area_id=area_id,
                                full_name=item["label"],
                                sex="unknown",
                                beneficiary_type="newborn",
                                status="active",
                                risk_level="none",
                                next_due_at=date.today().isoformat(),
                                created_at=now,
                                updated_at=now,
                                version=1,
                            )
                        )

    def reserve_local_code(self, worker_id: str, device_prefix: int | None = None) -> str:
        """Generate a unique per-worker numeric local code without colliding with existing codes."""
        with self._session_factory() as db:
            existing_codes = set(
                db.scalars(
                    select(Beneficiary.local_code).where(Beneficiary.worker_id == worker_id)
                ).all()
            )

        if device_prefix is not None:
            seq = 1
            while True:
                candidate = f"{device_prefix}{seq:03d}"
                if candidate not in existing_codes:
                    return candidate
                seq += 1

        max_num = 1000
        for code in existing_codes:
            if code.isdigit():
                max_num = max(max_num, int(code))
        next_num = max_num + 1
        while str(next_num) in existing_codes:
            next_num += 1
        return str(next_num)

    def create_beneficiary(
        self,
        *,
        beneficiary_id: str | None = None,
        local_code: str | None = None,
        worker_id: str,
        full_name: str,
        beneficiary_type: str = "newborn",
        sex: str = "unknown",
        dob: str | None = None,
        dob_is_estimated: bool = False,
        area_id: str | None = None,
        household_id: str | None = None,
        mother_id: str | None = None,
        phone_enc: str | None = None,
        external_id: str | None = None,
        lmp_date: str | None = None,
        gravida: int | None = None,
        parity: int | None = None,
        consent_given_by: str | None = "self",
        consent_method: str = "verbal",
        device_id: str = "backend",
    ) -> Beneficiary:
        """Create a beneficiary with optional consent record, pregnancy row, and initial due date."""
        bid = beneficiary_id or str(uuid.uuid4())
        code = local_code or self.reserve_local_code(worker_id)
        now = _utc_iso()
        parsed_dob = _parse_date(dob)
        parsed_lmp = _parse_date(lmp_date)
        initial_due = compute_next_due_at(
            beneficiary_type,
            dob=parsed_dob,
            lmp_date=parsed_lmp,
        )

        with self._session_factory() as db, db.begin():
            consent_id: str | None = None
            row = Beneficiary(
                id=bid,
                local_code=code,
                external_id=external_id,
                worker_id=worker_id,
                area_id=area_id,
                household_id=household_id,
                full_name=full_name.strip(),
                sex=sex,
                dob=dob,
                dob_is_estimated=dob_is_estimated,
                beneficiary_type=beneficiary_type,
                mother_id=mother_id,
                phone_enc=phone_enc,
                consent_id=None,
                status="active",
                risk_level="none",
                next_due_at=initial_due.isoformat() if initial_due else None,
                created_at=now,
                updated_at=now,
                version=1,
            )
            db.add(row)
            db.flush()

            if consent_given_by is not None:
                consent_id = str(uuid.uuid4())
                db.add(
                    Consent(
                        id=consent_id,
                        beneficiary_id=bid,
                        kind="beneficiary_registration",
                        given_by=consent_given_by,
                        method=consent_method,
                        policy_version="v2_2026_01",
                        given_at=now,
                    )
                )
                row.consent_id = consent_id

            if beneficiary_type == "pregnant_woman" and parsed_lmp is not None:
                edd = compute_edd(parsed_lmp)
                db.add(
                    Pregnancy(
                        id=str(uuid.uuid4()),
                        beneficiary_id=bid,
                        lmp_date=parsed_lmp.isoformat(),
                        edd_date=edd.isoformat(),
                        gravida=gravida,
                        parity=parity,
                        status="active",
                        created_at=now,
                        updated_at=now,
                    )
                )

            self._append_audit(
                db,
                actor_id=worker_id,
                action="beneficiary_created",
                entity="beneficiary",
                entity_id=bid,
                device_id=device_id,
                at=now,
            )
            return row

    def upsert_beneficiary_lww(
        self,
        *,
        beneficiary_id: str,
        local_code: str,
        worker_id: str,
        full_name: str,
        beneficiary_type: str = "newborn",
        sex: str = "unknown",
        dob: str | None = None,
        dob_is_estimated: bool = False,
        area_id: str | None = None,
        phone_enc: str | None = None,
        status: str = "active",
        updated_at: str,
        version: int,
        deleted_at: str | None = None,
    ) -> tuple[Beneficiary, bool]:
        """Upsert a beneficiary using last-write-wins ordering on (updated_at, version)."""
        with self._session_factory() as db, db.begin():
            existing = db.get(Beneficiary, beneficiary_id)
            if existing is None:
                row = Beneficiary(
                    id=beneficiary_id,
                    local_code=local_code,
                    worker_id=worker_id,
                    area_id=area_id,
                    full_name=full_name.strip(),
                    sex=sex,
                    dob=dob,
                    dob_is_estimated=dob_is_estimated,
                    beneficiary_type=beneficiary_type,
                    phone_enc=phone_enc,
                    status=status,
                    risk_level="none",
                    created_at=updated_at,
                    updated_at=updated_at,
                    deleted_at=deleted_at,
                    version=version,
                )
                db.add(row)
                self._append_audit(
                    db,
                    actor_id=worker_id,
                    action="beneficiary_upserted",
                    entity="beneficiary",
                    entity_id=beneficiary_id,
                )
                return row, True

            incoming_dt = _parse_iso_dt(updated_at)
            existing_dt = _parse_iso_dt(existing.updated_at)
            is_newer = (
                incoming_dt > existing_dt
                if (incoming_dt is not None and existing_dt is not None and incoming_dt != existing_dt)
                else (updated_at, version) > (existing.updated_at, existing.version)
            )
            if not is_newer:
                return existing, False

            existing.local_code = local_code
            existing.area_id = area_id
            existing.full_name = full_name.strip()
            existing.sex = sex
            existing.dob = dob
            existing.dob_is_estimated = dob_is_estimated
            existing.beneficiary_type = beneficiary_type
            existing.phone_enc = phone_enc
            existing.status = status
            existing.updated_at = updated_at
            existing.deleted_at = deleted_at
            existing.version = version
            self._append_audit(
                db,
                actor_id=worker_id,
                action="beneficiary_upserted",
                entity="beneficiary",
                entity_id=beneficiary_id,
            )
            return existing, True

    def get_beneficiary(self, beneficiary_id: str) -> Beneficiary | None:
        with self._session_factory() as db:
            return db.get(Beneficiary, beneficiary_id)

    def list_beneficiaries(
        self,
        worker_id: str,
        *,
        include_deleted: bool = False,
    ) -> list[Beneficiary]:
        with self._session_factory() as db:
            stmt = select(Beneficiary).where(Beneficiary.worker_id == worker_id)
            if not include_deleted:
                stmt = stmt.where(Beneficiary.deleted_at.is_(None), Beneficiary.status != "closed")
            stmt = stmt.order_by(Beneficiary.next_due_at.asc(), Beneficiary.local_code.asc())
            return list(db.scalars(stmt).all())

    def soft_delete_beneficiary(
        self,
        beneficiary_id: str,
        *,
        actor_id: str,
        device_id: str = "backend",
    ) -> Beneficiary:
        """Soft-delete a beneficiary without removing history or audit trail."""
        now = _utc_iso()
        with self._session_factory() as db, db.begin():
            row = db.get(Beneficiary, beneficiary_id)
            if row is None:
                raise LookupError(f"Beneficiary not found: {beneficiary_id}")
            row.deleted_at = now
            row.status = "closed"
            row.updated_at = now
            row.version += 1
            self._append_audit(
                db,
                actor_id=actor_id,
                action="beneficiary_soft_deleted",
                entity="beneficiary",
                entity_id=beneficiary_id,
                device_id=device_id,
                at=now,
            )
            return row

    def check_duplicates(
        self,
        *,
        worker_id: str,
        area_id: str | None,
        full_name: str,
        dob: str | None = None,
        phone_enc: str | None = None,
    ) -> list[DuplicateMatch]:
        """Screen active non-deleted beneficiaries in the same area for likely duplicates."""
        with self._session_factory() as db:
            rows = list(
                db.scalars(
                    select(Beneficiary).where(
                        Beneficiary.deleted_at.is_(None),
                        Beneficiary.status == "active",
                    )
                ).all()
            )

        existing_inputs = [
            DuplicateCandidateInput(
                id=r.id,
                local_code=r.local_code,
                full_name=r.full_name,
                worker_id=r.worker_id,
                area_id=r.area_id,
                dob=r.dob,
                phone_enc=r.phone_enc,
                status=r.status,
                deleted_at=r.deleted_at,
            )
            for r in rows
        ]
        candidate = DuplicateCandidateInput(
            id="__new__",
            local_code="",
            full_name=full_name,
            worker_id=worker_id,
            area_id=area_id,
            dob=dob,
            phone_enc=phone_enc,
        )
        return find_duplicate_candidates(candidate, existing_inputs)

    def create_draft_visit(
        self,
        *,
        visit_id: str | None = None,
        client_id: str | None = None,
        beneficiary_id: str | None,
        worker_id: str,
        visit_type_code: str = "newborn_home_visit",
        schema_version: int = 1,
        visited_at: str | None = None,
        payload: dict | None = None,
        risk_flags: list[str] | None = None,
        referral_suggested: bool = False,
        transcript_text: str = "",
        language: str = "hi",
        input_method: str = "voice",
        started_at: str | None = None,
    ) -> Visit:
        """Create a mutable draft visit before confirmation."""
        vid = visit_id or str(uuid.uuid4())
        now = _utc_iso()
        with self._session_factory() as db, db.begin():
            visit = Visit(
                id=vid,
                client_id=client_id,
                beneficiary_id=beneficiary_id,
                worker_id=worker_id,
                visit_type_code=visit_type_code,
                schema_version=schema_version,
                visited_at=visited_at or date.today().isoformat(),
                status="draft",
                payload_json=json.dumps(payload or {}),
                risk_flags_json=json.dumps(risk_flags or []),
                referral_suggested=referral_suggested,
                transcript_text=transcript_text,
                language=language,
                input_method=input_method,
                started_at=started_at or now,
                updated_at=now,
                version=1,
            )
            db.add(visit)
            return visit

    def _sync_measurements(self, db: Session, visit: Visit, payload: dict) -> None:
        existing = list(
            db.scalars(
                select(VisitMeasurement).where(VisitMeasurement.visit_id == visit.id)
            ).all()
        )
        for item in existing:
            db.delete(item)
        for key, value_num, unit in extract_numeric_measurements(payload):
            db.add(
                VisitMeasurement(
                    id=str(uuid.uuid4()),
                    visit_id=visit.id,
                    beneficiary_id=visit.beneficiary_id,
                    key=key,
                    value_num=value_num,
                    unit=unit,
                    measured_at=visit.visited_at,
                )
            )

    def confirm_visit(
        self,
        visit_id: str,
        *,
        actor_id: str | None = None,
        payload: dict | None = None,
        risk_flags: list[str] | None = None,
        referral_suggested: bool | None = None,
        interval_days: int | None = None,
        device_id: str = "backend",
    ) -> Visit:
        """Atomically confirm a draft visit, extract measurements, and update beneficiary caches."""
        now = _utc_iso()
        with self._session_factory() as db, db.begin():
            visit = db.get(Visit, visit_id)
            if visit is None:
                raise LookupError(f"Visit not found: {visit_id}")
            if visit.status in ("confirmed", "amended"):
                raise VisitImmutableError(
                    f"Visit {visit_id} is already {visit.status} and cannot be overwritten."
                )

            merged_payload = payload if payload is not None else json.loads(visit.payload_json)
            merged_flags = risk_flags if risk_flags is not None else json.loads(visit.risk_flags_json)
            merged_referral = (
                referral_suggested if referral_suggested is not None else visit.referral_suggested
            )

            next_due: str | None = None
            ben = db.get(Beneficiary, visit.beneficiary_id) if visit.beneficiary_id else None
            if ben is not None:
                active_preg = db.scalar(
                    select(Pregnancy).where(
                        Pregnancy.beneficiary_id == ben.id,
                        Pregnancy.status == "active",
                    )
                )
                due_date = compute_next_due_at(
                    ben.beneficiary_type,
                    dob=_parse_date(ben.dob),
                    visited_at=_parse_date(visit.visited_at) or date.today(),
                    lmp_date=_parse_date(active_preg.lmp_date) if active_preg else None,
                    interval_days=interval_days,
                )
                next_due = due_date.isoformat() if due_date else None
                if ben.last_visit_at is None or visit.visited_at >= ben.last_visit_at:
                    ben.last_visit_at = visit.visited_at
                ben.next_due_at = next_due
                ben.risk_level = derive_risk_level(merged_flags, merged_referral)
                ben.updated_at = now
                ben.version += 1

            visit.payload_json = json.dumps(merged_payload)
            visit.risk_flags_json = json.dumps(merged_flags)
            visit.referral_suggested = merged_referral
            visit.next_due_at = next_due
            visit.status = "confirmed"
            visit.confirmed_at = now
            visit.updated_at = now
            visit.version += 1

            self._sync_measurements(db, visit, merged_payload)
            self._append_audit(
                db,
                actor_id=actor_id or visit.worker_id,
                action="visit_confirmed",
                entity="visit",
                entity_id=visit.id,
                device_id=device_id,
                at=now,
            )
            return visit

    def amend_visit(
        self,
        visit_id: str,
        *,
        changed_by: str,
        changes: dict[str, object],
        reason: str,
        risk_flags: list[str] | None = None,
        referral_suggested: bool | None = None,
        device_id: str = "backend",
    ) -> tuple[Visit, VisitAmendment]:
        """Amend a confirmed visit via append-only VisitAmendment + refreshed measurements."""
        now = _utc_iso()
        with self._session_factory() as db, db.begin():
            visit = db.get(Visit, visit_id)
            if visit is None:
                raise LookupError(f"Visit not found: {visit_id}")
            if visit.status not in ("confirmed", "amended"):
                raise ValueError("Only confirmed visits can be amended.")

            payload = json.loads(visit.payload_json)
            diff: dict[str, dict[str, object]] = {}
            for key, after_val in changes.items():
                diff[key] = {"before": payload.get(key), "after": after_val}
                payload[key] = after_val

            amendment = VisitAmendment(
                id=str(uuid.uuid4()),
                visit_id=visit.id,
                changed_by=changed_by,
                changes_json=json.dumps(diff),
                reason=reason.strip(),
                created_at=now,
            )
            db.add(amendment)

            merged_flags = risk_flags if risk_flags is not None else json.loads(visit.risk_flags_json)
            merged_referral = (
                referral_suggested if referral_suggested is not None else visit.referral_suggested
            )

            visit.payload_json = json.dumps(payload)
            visit.risk_flags_json = json.dumps(merged_flags)
            visit.referral_suggested = merged_referral
            visit.status = "amended"
            visit.updated_at = now
            visit.version += 1

            self._sync_measurements(db, visit, payload)

            if visit.beneficiary_id:
                ben = db.get(Beneficiary, visit.beneficiary_id)
                if ben is not None:
                    ben.risk_level = derive_risk_level(merged_flags, merged_referral)
                    ben.updated_at = now
                    ben.version += 1

            self._append_audit(
                db,
                actor_id=changed_by,
                action="visit_amended",
                entity="visit",
                entity_id=visit.id,
                device_id=device_id,
                at=now,
            )
            return visit, amendment

    def get_visit(self, visit_id: str) -> Visit | None:
        with self._session_factory() as db:
            return db.get(Visit, visit_id)

    def get_visit_measurements(
        self,
        beneficiary_id: str,
        *,
        key: str | None = None,
    ) -> list[VisitMeasurement]:
        with self._session_factory() as db:
            stmt = select(VisitMeasurement).where(VisitMeasurement.beneficiary_id == beneficiary_id)
            if key is not None:
                stmt = stmt.where(VisitMeasurement.key == key)
            stmt = stmt.order_by(VisitMeasurement.measured_at.asc())
            return list(db.scalars(stmt).all())

    def get_visit_amendments(self, visit_id: str) -> list[VisitAmendment]:
        with self._session_factory() as db:
            return list(
                db.scalars(
                    select(VisitAmendment)
                    .where(VisitAmendment.visit_id == visit_id)
                    .order_by(VisitAmendment.created_at.asc())
                ).all()
            )

    def get_audit_logs(self, entity_id: str | None = None) -> list[AuditLogEntry]:
        with self._session_factory() as db:
            stmt = select(AuditLogEntry)
            if entity_id is not None:
                stmt = stmt.where(AuditLogEntry.entity_id == entity_id)
            return list(db.scalars(stmt.order_by(AuditLogEntry.at.asc())).all())

    def record_audio_asset(
        self,
        *,
        asset_id: str | None = None,
        visit_id: str | None,
        path: str,
        duration_ms: int = 0,
        state: str = "local",
        retention_days: int | None = None,
        created_at: datetime | None = None,
    ) -> AudioAsset:
        days = retention_days if retention_days is not None else get_settings().AUDIO_RETENTION_DAYS
        created_dt = created_at or _utc_now()
        delete_after_dt = created_dt + timedelta(days=days)
        aid = asset_id or str(uuid.uuid4())
        with self._session_factory() as db, db.begin():
            asset = AudioAsset(
                id=aid,
                visit_id=visit_id,
                path=path,
                duration_ms=duration_ms,
                state=state,
                delete_after=delete_after_dt.isoformat(),
                created_at=created_dt.isoformat(),
            )
            db.add(asset)
            return asset

    def purge_expired_audio(
        self,
        *,
        now: datetime | None = None,
        actor_id: str = "system_retention",
    ) -> list[str]:
        """Delete audio files that are uploaded+confirmed or past retention deadline (SPEC_V2 §5.6)."""
        ref_now = now or _utc_now()
        deleted_ids: list[str] = []

        with self._session_factory() as db, db.begin():
            assets = list(
                db.scalars(select(AudioAsset).where(AudioAsset.state != "deleted")).all()
            )
            for asset in assets:
                visit = db.get(Visit, asset.visit_id) if asset.visit_id else None
                synced_and_confirmed = (
                    asset.state == "uploaded"
                    and visit is not None
                    and visit.status in ("confirmed", "amended")
                )
                delete_dt = _parse_iso_dt(asset.delete_after)
                expired = delete_dt is not None and delete_dt <= ref_now

                if not (synced_and_confirmed or expired):
                    continue

                file_path = Path(asset.path)
                if file_path.exists() and file_path.is_file():
                    file_path.unlink(missing_ok=True)
                asset.state = "deleted"
                deleted_ids.append(asset.id)
                self._append_audit(
                    db,
                    actor_id=actor_id,
                    action="audio_deleted",
                    entity="audio_asset",
                    entity_id=asset.id,
                    at=ref_now.isoformat(),
                )

        return deleted_ids
