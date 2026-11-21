"""Deterministic clinical risk rules (SPEC §7 & §8.3). Never produced by an LLM."""

from __future__ import annotations

from app.core.config_loader import VisitTypeConfig
from app.schemas.newborn_visit import (
    Breastfeeding,
    CordStatus,
    DangerSign,
    NewbornVisitRecord,
)


def _in_range(field_name: str, value: float, config: VisitTypeConfig) -> bool:
    bounds = config.ranges.get(field_name)
    if bounds is None:
        return True
    return bounds.min <= value <= bounds.max


def evaluate(record: NewbornVisitRecord, config: VisitTypeConfig) -> tuple[list[str], bool]:
    """Compute deterministic risk_flags and referral_suggested from config thresholds."""
    flags: list[str] = []

    def add_flag(name: str) -> None:
        if name not in flags:
            flags.append(name)

    thresholds = config.risk_thresholds

    # Numeric rules skip out-of-range (untrusted/flagged) values.
    weight = record.baby_weight_kg
    if weight is not None and weight.value is not None:
        if _in_range("baby_weight_kg", weight.value, config):
            if weight.value < thresholds.low_birth_weight_kg_below:
                add_flag("low_birth_weight")

    temp = record.temperature_c
    if temp is not None and temp.value is not None:
        if _in_range("temperature_c", temp.value, config):
            if temp.value >= thresholds.fever_c_at_or_above:
                add_flag("fever")
            if temp.value < thresholds.hypothermia_c_below:
                add_flag("hypothermia")

    breathing = record.breathing_rate_per_min
    if breathing is not None and breathing.value is not None:
        if _in_range("breathing_rate_per_min", breathing.value, config):
            if breathing.value > thresholds.fast_breathing_above:
                add_flag("fast_breathing")

    cord = record.cord_status
    if cord is not None and cord.value is not None:
        if cord.value in (CordStatus.red_swollen, CordStatus.pus_discharge):
            add_flag("cord_infection")

    feeding = record.breastfeeding
    if feeding is not None and feeding.value is not None:
        if feeding.value == Breastfeeding.not_feeding:
            add_flag("not_feeding")

    jaundice = record.jaundice
    if jaundice is not None and jaundice.value is True:
        add_flag("jaundice")

    limb = record.limb_abnormality
    if limb is not None and limb.value is not None and limb.value.present:
        add_flag("limb_abnormality")

    danger_signs = record.danger_signs
    if danger_signs is not None and danger_signs.value:
        for sign in danger_signs.value:
            sign_name = sign.value if isinstance(sign, DangerSign) else str(sign)
            add_flag(f"danger_sign:{sign_name}")

    high_risk = set(config.high_risk_flags)
    referral_suggested = any(
        (flag in high_risk or flag.split(":", 1)[0] in high_risk) for flag in flags
    )
    return flags, referral_suggested


def apply_risk(record: NewbornVisitRecord, config: VisitTypeConfig) -> NewbornVisitRecord:
    """Return a copy of the record with computed risk_flags and referral_suggested."""
    updated = record.model_copy(deep=True)
    flags, referral_suggested = evaluate(updated, config)
    updated.risk_flags = flags
    updated.referral_suggested = referral_suggested
    return updated
