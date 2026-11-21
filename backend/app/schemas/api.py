"""API request and response schemas for SPEC §10 endpoints."""

from __future__ import annotations

from datetime import date
from typing import Literal

from pydantic import BaseModel, Field

from app.schemas.newborn_visit import (
    Breastfeeding,
    CordStatus,
    DangerSign,
    FieldSource,
    Flag,
    LimbAbnormality,
    NewbornVisitRecord,
)
from app.services.followup import FollowupPayload


class VisitTurnResponse(BaseModel):
    """Response for POST /v1/visits/audio and POST /v1/visits/{id}/answer."""

    session_id: str
    transcript: str
    record: NewbornVisitRecord
    flags: list[Flag] = Field(default_factory=list)
    risk_flags: list[str] = Field(default_factory=list)
    referral_suggested: bool = False
    status: Literal["needs_followup", "ready_to_confirm", "error_retry"]
    followup: FollowupPayload | None = None
    visit_type_code: str = "newborn_home_visit"
    schema_version: int = 1


class RecordPatchRequest(BaseModel):
    """Partial field edits submitted from the confirmation screen."""

    beneficiary_id: str | None = None
    baby_weight_kg: float | None = None
    temperature_c: float | None = None
    breastfeeding: Breastfeeding | None = None
    cord_status: CordStatus | None = None
    jaundice: bool | None = None
    breathing_rate_per_min: int | None = None
    limb_abnormality: LimbAbnormality | None = None
    danger_signs: list[DangerSign] | None = None
    mother_notes: str | None = None
    notes: str | None = None
    source: FieldSource = FieldSource.typed


class RecordPatchResponse(BaseModel):
    """Response returned after PATCH /v1/visits/{id}/record."""

    session_id: str
    record: NewbornVisitRecord
    flags: list[Flag] = Field(default_factory=list)
    risk_flags: list[str] = Field(default_factory=list)
    referral_suggested: bool = False
    status: str


class ConfirmResponse(BaseModel):
    """Response returned by POST /v1/visits/{id}/confirm."""

    visit_id: str
    status: Literal["saved"] = "saved"


class ReadbackResponse(BaseModel):
    """Spoken read-back confirmation text and synthesized audio URL."""

    text: str
    audio_url: str | None = None


class SyncItemRequest(BaseModel):
    """Single queued offline recording sent in POST /v1/sync."""

    client_id: str
    audio_base64: str
    filename: str = "recording.wav"
    language: str
    visit_type: str = "newborn_home_visit"
    beneficiary_id: str | None = None
    asha_id: str = "asha_001"
    recorded_at: str | None = None


class SyncItemResult(BaseModel):
    """Per-item result returned by POST /v1/sync."""

    client_id: str
    ok: bool
    result: VisitTurnResponse | None = None
    error: dict[str, str] | None = None


class SyncResponse(BaseModel):
    """Batch response returned by POST /v1/sync."""

    results: list[SyncItemResult]


class VisitSummary(BaseModel):
    """Summary item returned by GET /v1/visits."""

    visit_id: str | None = None
    session_id: str
    asha_id: str | None = None
    beneficiary_id: str | None = None
    visit_date: date | None = None
    risk_flags: list[str] = Field(default_factory=list)
    referral_suggested: bool = False
    status: str
    updated_at: str


class WorkerProfile(BaseModel):
    """Authenticated ASHA worker profile returned by POST /v1/auth/login."""

    id: str
    worker_code: str
    name: str
    area: str


class LoginRequest(BaseModel):
    """Worker code + PIN login payload (SPEC_V2 §3.1, §9)."""

    worker_code: str
    pin: str


class LoginResponse(BaseModel):
    """Session token and worker profile issued on login."""

    token: str
    worker: WorkerProfile


class VisitTypeFieldOut(BaseModel):
    """Public field schema descriptor exposed by GET /v1/visit-types."""

    key: str
    type: str
    required: bool = False
    min: float | None = None
    max: float | None = None
    unit: str | None = None


class VisitTypeOut(BaseModel):
    """Visit purpose metadata served by GET /v1/visit-types (SPEC_V2 §4.1, §9)."""

    code: str
    schema_version: int
    name: dict[str, str]
    description: dict[str, str]
    applies_to: list[str]
    required_fields: list[str]
    fields: list[VisitTypeFieldOut] = Field(default_factory=list)
    voice_keywords: list[str] = Field(default_factory=list)
    active: bool = True


class DetectedPurposeOut(BaseModel):
    """Detected visit purpose from a spoken hint phrase."""

    code: str
    confidence: float
    matched_keyword: str


class SuggestedPurposeResponse(BaseModel):
    """Response for GET /v1/beneficiaries/{id}/suggested-purpose."""

    beneficiary_id: str
    suggested_code: str
    reason: dict[str, str]
    other_codes: list[str]
    detected_purpose: DetectedPurposeOut | None = None


class BeneficiaryCreateRequest(BaseModel):
    """Create a new beneficiary with consent (SPEC_V2 §3.4, §9)."""

    worker_id: str = "asha_001"
    full_name: str
    beneficiary_type: Literal[
        "pregnant_woman",
        "newborn",
        "pnc_mother",
        "child_u5",
        "adult",
        "other",
    ] = "newborn"
    sex: Literal["female", "male", "unknown"] = "unknown"
    dob: str | None = None
    dob_is_estimated: bool = False
    area_id: str | None = None
    area_note: str | None = None
    household_id: str | None = None
    mother_id: str | None = None
    phone: str | None = None
    external_id: str | None = None
    lmp_date: str | None = None
    pregnancy_months: int | None = None
    consent_given: bool = False
    consent_given_by: Literal["self", "guardian"] = "self"
    consent_method: Literal["verbal", "signed"] = "verbal"
    local_code: str | None = None
    beneficiary_id: str | None = None


class BeneficiaryPatchRequest(BaseModel):
    """Partial editable update for an existing beneficiary."""

    full_name: str | None = None
    sex: Literal["female", "male", "unknown"] | None = None
    dob: str | None = None
    dob_is_estimated: bool | None = None
    beneficiary_type: Literal[
        "pregnant_woman",
        "newborn",
        "pnc_mother",
        "child_u5",
        "adult",
        "other",
    ] | None = None
    area_id: str | None = None
    phone: str | None = None
    status: Literal["active", "transferred", "closed"] | None = None


class BeneficiaryOut(BaseModel):
    """Backwards-compatible V1+V2 beneficiary profile representation."""

    id: str
    label: str
    uuid: str
    local_code: str
    full_name: str
    beneficiary_type: str = "newborn"
    sex: str = "unknown"
    dob: str | None = None
    dob_is_estimated: bool = False
    area_id: str | None = None
    area_name: str | None = None
    mother_id: str | None = None
    phone_masked: str | None = None
    has_phone: bool = False
    consent_id: str | None = None
    status: str = "active"
    risk_level: str = "none"
    last_visit_at: str | None = None
    next_due_at: str | None = None
    edd_date: str | None = None
    version: int = 1


class DuplicateCheckRequest(BaseModel):
    """Payload for POST /v1/beneficiaries/check-duplicate."""

    worker_id: str = "asha_001"
    area_id: str | None = None
    full_name: str
    dob: str | None = None
    phone: str | None = None


class DuplicateCandidateOut(BaseModel):
    """Scored candidate duplicate returned to UI (never auto-merged)."""

    beneficiary_id: str
    local_code: str
    full_name: str
    dob: str | None = None
    score: float
    reasons: list[str]


class BeneficiarySpeechDraftOut(BaseModel):
    """Editable beneficiary fields extracted from speak-to-add audio."""

    full_name: str
    beneficiary_type: str = "other"
    sex: str = "unknown"
    dob: str | None = None
    dob_is_estimated: bool = False
    age_years: int | None = None
    age_days: int | None = None
    pregnancy_months: int | None = None
    lmp_date: str | None = None
    edd_date: str | None = None
    area_note: str | None = None
    phone: str | None = None


class BeneficiaryFromAudioResponse(BaseModel):
    """Response for POST /v1/beneficiaries/from-audio."""

    transcript: str
    draft: BeneficiarySpeechDraftOut
    duplicate_candidates: list[DuplicateCandidateOut] = Field(default_factory=list)


class MeasurementPointOut(BaseModel):
    """Normalized measurement data point for profile trend charts."""

    key: str
    value_num: float
    unit: str
    measured_at: str


class BeneficiaryVisitsResponse(BaseModel):
    """Merged timeline + trend measurements for a beneficiary profile."""

    beneficiary_id: str
    visits: list[VisitSummary] = Field(default_factory=list)
    measurements: list[MeasurementPointOut] = Field(default_factory=list)


class StatsSummaryOut(BaseModel):
    """SPEC_V2 §6.1 summary metrics response."""

    period: str
    start_date: str
    end_date: str
    visits_done: int
    due_today: int
    overdue: int
    active_beneficiaries: int
    coverage: float
    high_risk_open: int
    referrals_suggested: int
    avg_record_seconds: float | None = None
    voice_share: float | None = None
    followup_rate: float | None = None
    has_demo_data: bool = False


class TimeseriesPointOut(BaseModel):
    """Daily confirmed visit point for bar chart."""

    date: str
    count: int
    high_risk_count: int = 0


class CategoryCountOut(BaseModel):
    """Purpose or risk breakdown bar item."""

    key: str
    label: str
    count: int
    share: float


class DueListItemOut(BaseModel):
    """Compact overdue / due-today beneficiary item."""

    beneficiary_id: str
    local_code: str
    full_name: str
    beneficiary_type: str
    next_due_at: str
    days_overdue: int
    risk_level: str
    last_visit_at: str | None = None
