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
