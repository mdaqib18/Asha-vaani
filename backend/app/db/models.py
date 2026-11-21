"""SQLAlchemy 2.0 V2 schema definitions (SPEC_V2 §5.1, §5.2)."""

from __future__ import annotations

from sqlalchemy import (
    Boolean,
    Float,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
)
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column


class Base(DeclarativeBase):
    """Declarative base for all V2 database tables (SQLite and Postgres compatible)."""


class Worker(Base):
    __tablename__ = "workers"

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    worker_code: Mapped[str] = mapped_column(String(64), unique=True, nullable=False)
    name: Mapped[str] = mapped_column(String(200), nullable=False)
    language_pref: Mapped[str] = mapped_column(String(16), nullable=False, default="hi")
    area_ids: Mapped[str] = mapped_column(Text, nullable=False, default="[]")
    pin_hash: Mapped[str] = mapped_column(String(128), nullable=False, default="")
    created_at: Mapped[str] = mapped_column(String(64), nullable=False)


class Area(Base):
    __tablename__ = "areas"

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    name: Mapped[str] = mapped_column(String(200), nullable=False)
    code: Mapped[str] = mapped_column(String(64), unique=True, nullable=False)


class Household(Base):
    __tablename__ = "households"

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    area_id: Mapped[str] = mapped_column(ForeignKey("areas.id"), nullable=False)
    note: Mapped[str] = mapped_column(Text, nullable=False, default="")
    created_at: Mapped[str] = mapped_column(String(64), nullable=False)


class Beneficiary(Base):
    __tablename__ = "beneficiaries"
    __table_args__ = (
        Index("ix_beneficiaries_worker_status_due", "worker_id", "status", "next_due_at"),
        Index("uq_beneficiaries_worker_local_code", "worker_id", "local_code", unique=True),
    )

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    local_code: Mapped[str] = mapped_column(String(32), nullable=False)
    external_id: Mapped[str | None] = mapped_column(String(64), nullable=True)
    worker_id: Mapped[str] = mapped_column(ForeignKey("workers.id"), nullable=False)
    area_id: Mapped[str | None] = mapped_column(ForeignKey("areas.id"), nullable=True)
    household_id: Mapped[str | None] = mapped_column(ForeignKey("households.id"), nullable=True)
    full_name: Mapped[str] = mapped_column(String(200), nullable=False)
    sex: Mapped[str] = mapped_column(String(16), nullable=False, default="unknown")
    dob: Mapped[str | None] = mapped_column(String(32), nullable=True)
    dob_is_estimated: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    beneficiary_type: Mapped[str] = mapped_column(String(32), nullable=False, default="newborn")
    mother_id: Mapped[str | None] = mapped_column(ForeignKey("beneficiaries.id"), nullable=True)
    phone_enc: Mapped[str | None] = mapped_column(Text, nullable=True)
    consent_id: Mapped[str | None] = mapped_column(String(64), nullable=True)
    status: Mapped[str] = mapped_column(String(24), nullable=False, default="active")
    risk_level: Mapped[str] = mapped_column(String(16), nullable=False, default="none")
    last_visit_at: Mapped[str | None] = mapped_column(String(64), nullable=True)
    next_due_at: Mapped[str | None] = mapped_column(String(64), nullable=True)
    created_at: Mapped[str] = mapped_column(String(64), nullable=False)
    updated_at: Mapped[str] = mapped_column(String(64), nullable=False)
    deleted_at: Mapped[str | None] = mapped_column(String(64), nullable=True)
    version: Mapped[int] = mapped_column(Integer, nullable=False, default=1)


class Pregnancy(Base):
    __tablename__ = "pregnancies"

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    beneficiary_id: Mapped[str] = mapped_column(ForeignKey("beneficiaries.id"), nullable=False)
    lmp_date: Mapped[str | None] = mapped_column(String(32), nullable=True)
    edd_date: Mapped[str | None] = mapped_column(String(32), nullable=True)
    gravida: Mapped[int | None] = mapped_column(Integer, nullable=True)
    parity: Mapped[int | None] = mapped_column(Integer, nullable=True)
    outcome: Mapped[str | None] = mapped_column(String(64), nullable=True)
    status: Mapped[str] = mapped_column(String(24), nullable=False, default="active")
    created_at: Mapped[str] = mapped_column(String(64), nullable=False)
    updated_at: Mapped[str] = mapped_column(String(64), nullable=False)


class VisitTypeRecord(Base):
    __tablename__ = "visit_types"

    code: Mapped[str] = mapped_column(String(64), primary_key=True)
    schema_version: Mapped[int] = mapped_column(Integer, nullable=False, default=1)
    name_i18n: Mapped[str] = mapped_column(Text, nullable=False, default="{}")
    active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)


class Visit(Base):
    __tablename__ = "visits"
    __table_args__ = (
        Index("ix_visits_worker_visited", "worker_id", "visited_at"),
    )

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    client_id: Mapped[str | None] = mapped_column(String(64), unique=True, nullable=True)
    beneficiary_id: Mapped[str | None] = mapped_column(ForeignKey("beneficiaries.id"), nullable=True)
    worker_id: Mapped[str] = mapped_column(ForeignKey("workers.id"), nullable=False)
    visit_type_code: Mapped[str] = mapped_column(
        String(64), nullable=False, default="newborn_home_visit"
    )
    schema_version: Mapped[int] = mapped_column(Integer, nullable=False, default=1)
    visited_at: Mapped[str] = mapped_column(String(64), nullable=False)
    status: Mapped[str] = mapped_column(String(24), nullable=False, default="draft")
    payload_json: Mapped[str] = mapped_column(Text, nullable=False, default="{}")
    risk_flags_json: Mapped[str] = mapped_column(Text, nullable=False, default="[]")
    referral_suggested: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    next_due_at: Mapped[str | None] = mapped_column(String(64), nullable=True)
    transcript_text: Mapped[str] = mapped_column(Text, nullable=False, default="")
    language: Mapped[str] = mapped_column(String(16), nullable=False, default="hi")
    input_method: Mapped[str] = mapped_column(String(16), nullable=False, default="voice")
    started_at: Mapped[str | None] = mapped_column(String(64), nullable=True)
    confirmed_at: Mapped[str | None] = mapped_column(String(64), nullable=True)
    updated_at: Mapped[str] = mapped_column(String(64), nullable=False)
    version: Mapped[int] = mapped_column(Integer, nullable=False, default=1)


Index("ix_visits_beneficiary_visited", Visit.beneficiary_id, Visit.visited_at.desc())


class VisitMeasurement(Base):
    __tablename__ = "visit_measurements"
    __table_args__ = (
        Index("ix_visit_measurements_ben_key_at", "beneficiary_id", "key", "measured_at"),
    )

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    visit_id: Mapped[str] = mapped_column(ForeignKey("visits.id"), nullable=False)
    beneficiary_id: Mapped[str | None] = mapped_column(ForeignKey("beneficiaries.id"), nullable=True)
    key: Mapped[str] = mapped_column(String(64), nullable=False)
    value_num: Mapped[float] = mapped_column(Float, nullable=False)
    unit: Mapped[str] = mapped_column(String(24), nullable=False, default="")
    measured_at: Mapped[str] = mapped_column(String(64), nullable=False)


class VisitAmendment(Base):
    __tablename__ = "visit_amendments"

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    visit_id: Mapped[str] = mapped_column(ForeignKey("visits.id"), nullable=False)
    changed_by: Mapped[str] = mapped_column(String(64), nullable=False)
    changes_json: Mapped[str] = mapped_column(Text, nullable=False)
    reason: Mapped[str] = mapped_column(Text, nullable=False, default="")
    created_at: Mapped[str] = mapped_column(String(64), nullable=False)


class FollowupRecord(Base):
    __tablename__ = "followups"

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    visit_id: Mapped[str] = mapped_column(ForeignKey("visits.id"), nullable=False)
    question_text: Mapped[str] = mapped_column(Text, nullable=False)
    target_fields: Mapped[str] = mapped_column(Text, nullable=False, default="[]")
    answer_text: Mapped[str] = mapped_column(Text, nullable=False, default="")
    created_at: Mapped[str] = mapped_column(String(64), nullable=False)


class AudioAsset(Base):
    __tablename__ = "audio_assets"

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    visit_id: Mapped[str | None] = mapped_column(ForeignKey("visits.id"), nullable=True)
    path: Mapped[str] = mapped_column(Text, nullable=False)
    duration_ms: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    state: Mapped[str] = mapped_column(String(24), nullable=False, default="local")
    delete_after: Mapped[str | None] = mapped_column(String(64), nullable=True)
    created_at: Mapped[str] = mapped_column(String(64), nullable=False)


class Consent(Base):
    __tablename__ = "consents"

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    beneficiary_id: Mapped[str] = mapped_column(ForeignKey("beneficiaries.id"), nullable=False)
    kind: Mapped[str] = mapped_column(String(32), nullable=False, default="beneficiary_registration")
    given_by: Mapped[str] = mapped_column(String(16), nullable=False, default="self")
    method: Mapped[str] = mapped_column(String(16), nullable=False, default="verbal")
    policy_version: Mapped[str] = mapped_column(String(32), nullable=False, default="v2_2026_01")
    given_at: Mapped[str] = mapped_column(String(64), nullable=False)


class SyncQueueItem(Base):
    __tablename__ = "sync_queue"

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    entity: Mapped[str] = mapped_column(String(32), nullable=False)
    entity_id: Mapped[str] = mapped_column(String(64), nullable=False)
    op: Mapped[str] = mapped_column(String(24), nullable=False)
    attempts: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    last_error: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[str] = mapped_column(String(64), nullable=False)


class AuditLogEntry(Base):
    __tablename__ = "audit_log"

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    actor_id: Mapped[str] = mapped_column(String(64), nullable=False)
    action: Mapped[str] = mapped_column(String(64), nullable=False)
    entity: Mapped[str] = mapped_column(String(32), nullable=False)
    entity_id: Mapped[str] = mapped_column(String(64), nullable=False)
    device_id: Mapped[str] = mapped_column(String(64), nullable=False, default="backend")
    at: Mapped[str] = mapped_column(String(64), nullable=False)
