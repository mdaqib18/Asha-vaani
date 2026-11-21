from functools import lru_cache
from pathlib import Path

import yaml
from pydantic import BaseModel

_APP_DIR = Path(__file__).resolve().parent.parent
_VISIT_TYPES_DIR = _APP_DIR / "config" / "visit_types"

VISIT_TYPE_FILES: dict[str, str] = {
    "newborn_home_visit": "newborn.yaml",
}


class NumericRange(BaseModel):
    """Inclusive plausible range bounds for a numeric field."""

    min: float
    max: float


class RiskThresholds(BaseModel):
    """Deterministic clinical risk-flag thresholds."""

    low_birth_weight_kg_below: float
    fever_c_at_or_above: float
    hypothermia_c_below: float
    fast_breathing_above: int


class VisitTypeConfig(BaseModel):
    """Schema for visit-type YAML configuration."""

    visit_type: str
    required_fields: list[str]
    ranges: dict[str, NumericRange]
    risk_thresholds: RiskThresholds
    high_risk_flags: list[str]
    confirm_always: list[str]


@lru_cache(maxsize=8)
def load_visit_config(visit_type: str = "newborn_home_visit") -> VisitTypeConfig:
    """Load and validate a visit-type YAML configuration."""
    filename = VISIT_TYPE_FILES.get(visit_type)
    if filename is None:
        raise ValueError(f"Unsupported visit_type: {visit_type!r}")
    config_path = _VISIT_TYPES_DIR / filename
    with config_path.open("r", encoding="utf-8") as fh:
        raw = yaml.safe_load(fh)
    return VisitTypeConfig.model_validate(raw)
