from datetime import date
from enum import Enum
from typing import Generic, TypeVar

from pydantic import BaseModel, Field

T = TypeVar("T")


class Breastfeeding(str, Enum):
    exclusive = "exclusive"
    partial = "partial"
    not_feeding = "not_feeding"
    unknown = "unknown"


class CordStatus(str, Enum):
    clean_dry = "clean_dry"
    red_swollen = "red_swollen"
    pus_discharge = "pus_discharge"
    unknown = "unknown"


class LimbLocation(str, Enum):
    left_arm = "left_arm"
    right_arm = "right_arm"
    left_leg = "left_leg"
    right_leg = "right_leg"
    both_arms = "both_arms"
    both_legs = "both_legs"
    unspecified = "unspecified"


class DangerSign(str, Enum):
    not_feeding = "not_feeding"
    convulsions = "convulsions"
    lethargy = "lethargy"
    fast_breathing = "fast_breathing"
    fever = "fever"
    hypothermia = "hypothermia"
    pus_umbilicus = "pus_umbilicus"


class FieldSource(str, Enum):
    speech = "speech"
    typed = "typed"
    selected = "selected"


class LimbAbnormality(BaseModel):
    present: bool
    location: LimbLocation | None = None
    description: str | None = None


class ExtractedField(BaseModel, Generic[T]):
    """Wrapper for extracted field value and provenance metadata."""

    value: T | None = None
    confidence: float = Field(default=1.0, ge=0.0, le=1.0)
    source: FieldSource = FieldSource.speech
    needs_confirmation: bool = False


class NewbornVisitRecord(BaseModel):
    """Structured record for a newborn home visit (SPEC §7)."""

    beneficiary_id: ExtractedField[str] | None = None
    visit_date: date | None = None
    baby_weight_kg: ExtractedField[float] | None = None
    temperature_c: ExtractedField[float] | None = None
    breastfeeding: ExtractedField[Breastfeeding] | None = None
    cord_status: ExtractedField[CordStatus] | None = None
    jaundice: ExtractedField[bool] | None = None
    breathing_rate_per_min: ExtractedField[int] | None = None
    limb_abnormality: ExtractedField[LimbAbnormality] | None = None
    danger_signs: ExtractedField[list[DangerSign]] | None = None
    mother_notes: ExtractedField[str] | None = None
    notes: ExtractedField[str] | None = None
    risk_flags: list[str] = Field(default_factory=list)
    referral_suggested: bool = False


class Flag(BaseModel):
    """Validation flag emitted for out-of-range, unknown, or missing fields."""

    field: str
    reason: str
