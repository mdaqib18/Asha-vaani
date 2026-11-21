"""Auto-discovering YAML visit-type registry loader (SPEC_V2 §4)."""

from __future__ import annotations

from functools import lru_cache
from pathlib import Path

import yaml
from pydantic import BaseModel, Field

_APP_DIR = Path(__file__).resolve().parent.parent
_VISIT_TYPES_DIR = _APP_DIR / "config" / "visit_types"

_PREFERRED_ORDER = (
    "newborn_home_visit",
    "anc_visit",
    "pnc_mother_visit",
    "child_growth_immunization",
    "general_illness",
    "ncd_screening",
)


class NumericRange(BaseModel):
    """Inclusive plausible range bounds for a numeric field."""

    min: float
    max: float


class RiskThresholds(BaseModel):
    """Legacy newborn clinical risk-flag thresholds."""

    low_birth_weight_kg_below: float = 2.5
    fever_c_at_or_above: float = 37.5
    hypothermia_c_below: float = 35.5
    fast_breathing_above: int = 60


class FieldSpec(BaseModel):
    """Declarative field schema entry inside a visit-type YAML config."""

    key: str
    type: str = "string"
    required: bool = False
    min: float | None = None
    max: float | None = None
    unit: str | None = None


class DueRule(BaseModel):
    """Follow-up schedule rule attached to a visit purpose."""

    schedule_days: list[int] = Field(default_factory=list)
    interval_days: int | None = None


class RiskRuleSpec(BaseModel):
    """Deterministic risk rule expression defined in YAML."""

    id: str
    when: str
    flag: str
    severity: str = "high"


class VisitTypeConfig(BaseModel):
    """Schema for visit-type YAML configuration (V1 + V2 registry)."""

    visit_type: str
    code: str | None = None
    schema_version: int = 1
    active: bool = True
    name: dict[str, str] = Field(default_factory=dict)
    description: dict[str, str] = Field(default_factory=dict)
    applies_to: list[str] = Field(default_factory=list)
    due_rule: DueRule = Field(default_factory=DueRule)
    required_fields: list[str] = Field(default_factory=list)
    fields: list[FieldSpec] = Field(default_factory=list)
    ranges: dict[str, NumericRange] = Field(default_factory=dict)
    risk_thresholds: RiskThresholds = Field(default_factory=RiskThresholds)
    risk_rules: list[RiskRuleSpec] = Field(default_factory=list)
    high_risk_flags: list[str] = Field(default_factory=list)
    confirm_always: list[str] = Field(default_factory=list)
    followup_templates: dict[str, dict[str, str]] = Field(default_factory=dict)
    voice_keywords: list[str] = Field(default_factory=list)

    @property
    def effective_code(self) -> str:
        return self.code or self.visit_type


def _discover_visit_files() -> dict[str, Path]:
    registry: dict[str, Path] = {}
    if not _VISIT_TYPES_DIR.exists():
        return registry
    for path in sorted(_VISIT_TYPES_DIR.glob("*.yaml")):
        with path.open("r", encoding="utf-8") as fh:
            raw = yaml.safe_load(fh) or {}
        code = raw.get("code") or raw.get("visit_type")
        if isinstance(code, str) and code.strip():
            registry[code.strip()] = path
    return registry


VISIT_TYPE_FILES: dict[str, str] = {
    code: path.name for code, path in _discover_visit_files().items()
}


@lru_cache(maxsize=32)
def load_visit_config(visit_type: str = "newborn_home_visit") -> VisitTypeConfig:
    """Load and validate a visit-type YAML configuration."""
    files = _discover_visit_files()
    config_path = files.get(visit_type)
    if config_path is None:
        raise ValueError(f"Unsupported visit_type: {visit_type!r}")
    with config_path.open("r", encoding="utf-8") as fh:
        raw = yaml.safe_load(fh)
    return VisitTypeConfig.model_validate(raw)


def list_visit_configs(active_only: bool = True) -> list[VisitTypeConfig]:
    """Return all registered visit-type configurations in deterministic display order."""
    configs: list[VisitTypeConfig] = []
    for code in _discover_visit_files():
        cfg = load_visit_config(code)
        if active_only and not cfg.active:
            continue
        configs.append(cfg)

    rank = {code: idx for idx, code in enumerate(_PREFERRED_ORDER)}
    configs.sort(key=lambda c: (rank.get(c.effective_code, 999), c.effective_code))
    return configs
