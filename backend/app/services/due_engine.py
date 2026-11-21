"""Deterministic follow-up due-date and risk-level calculation engine (SPEC_V2 §4.3, §5.2)."""

from __future__ import annotations

from datetime import date, timedelta

# HBNC home-based newborn care visit day offsets from DOB (# TODO(verify) with ANM/NHM guidance).
NEWBORN_SCHEDULE_DAYS: tuple[int, ...] = (3, 7, 14, 21, 28, 42)
PNC_SCHEDULE_DAYS: tuple[int, ...] = (3, 7, 14, 42)

HIGH_RISK_FLAGS: frozenset[str] = frozenset(
    {
        "low_birth_weight",
        "hypothermia",
        "fever",
        "elevated_temperature",
        "fast_breathing",
        "not_feeding",
        "cord_infection",
        "jaundice_present",
        "danger_signs_present",
        "limb_abnormality_reported",
        "high_blood_pressure",
        "severe_anemia",
        "heavy_bleeding",
        "severe_acute_malnutrition",
        "persistent_fever",
        "critical_hyperglycemia",
    }
)


def compute_edd(lmp_date: date) -> date:
    """Compute Estimated Date of Delivery using Naegele's 280-day rule."""
    return lmp_date + timedelta(days=280)


def compute_next_due_at(
    beneficiary_type: str,
    *,
    dob: date | None = None,
    visited_at: date | None = None,
    lmp_date: date | None = None,
    interval_days: int | None = None,
    today: date | None = None,
) -> date | None:
    """Compute the next due visit date from beneficiary type, dates, and schedule rules."""
    ref_today = today or date.today()
    btype = (beneficiary_type or "newborn").strip().lower()

    if btype == "newborn":
        if dob is not None:
            anchor = visited_at or ref_today
            age_days = max(0, (anchor - dob).days)
            for target_day in NEWBORN_SCHEDULE_DAYS:
                if visited_at is not None:
                    if target_day > age_days:
                        return dob + timedelta(days=target_day)
                else:
                    if target_day >= age_days:
                        return dob + timedelta(days=target_day)
            return None
        days = interval_days if interval_days is not None else 7
        return (visited_at + timedelta(days=days)) if visited_at is not None else ref_today

    if btype == "pregnant_woman":
        days = interval_days if interval_days is not None else 30
        if visited_at is not None:
            next_date = visited_at + timedelta(days=days)
            if lmp_date is not None:
                edd = compute_edd(lmp_date)
                if next_date > edd + timedelta(days=14):
                    return edd
            return next_date
        return ref_today

    if btype == "pnc_mother":
        if dob is not None:
            anchor = visited_at or ref_today
            days_since_delivery = max(0, (anchor - dob).days)
            for target_day in PNC_SCHEDULE_DAYS:
                if visited_at is not None:
                    if target_day > days_since_delivery:
                        return dob + timedelta(days=target_day)
                else:
                    if target_day >= days_since_delivery:
                        return dob + timedelta(days=target_day)
            return None
        days = interval_days if interval_days is not None else 7
        return (visited_at + timedelta(days=days)) if visited_at is not None else ref_today

    if btype == "child_u5":
        days = interval_days if interval_days is not None else 30
        return (visited_at + timedelta(days=days)) if visited_at is not None else ref_today

    if interval_days is not None and interval_days > 0:
        return (visited_at or ref_today) + timedelta(days=interval_days)
    return None


def derive_risk_level(
    risk_flags: list[str],
    referral_suggested: bool = False,
    severities: dict[str, str] | None = None,
) -> str:
    """Derive beneficiary summary risk cache ('none' | 'watch' | 'high')."""
    if referral_suggested:
        return "high"

    severity_map = severities or {}
    for flag in risk_flags:
        if severity_map.get(flag) == "high" or flag in HIGH_RISK_FLAGS:
            return "high"

    if risk_flags or any(sev in ("watch", "medium") for sev in severity_map.values()):
        return "watch"

    return "none"
