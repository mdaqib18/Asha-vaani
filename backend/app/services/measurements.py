"""Normalization helpers for extracting chart-ready numeric visit measurements."""

from __future__ import annotations

MEASUREMENT_UNITS: dict[str, str] = {
    "baby_weight_kg": "kg",
    "weight_kg": "kg",
    "temperature_c": "C",
    "breathing_rate_per_min": "/min",
    "gestation_weeks": "weeks",
    "bp_systolic": "mmHg",
    "bp_diastolic": "mmHg",
    "hb_g_dl": "g/dL",
    "muac_cm": "cm",
    "random_blood_sugar_mg_dl": "mg/dL",
    "ifa_tablets_taken": "tablets",
}


def extract_numeric_measurements(payload: dict) -> list[tuple[str, float, str]]:
    """Extract (key, value_num, unit) tuples from a structured visit payload dict."""
    items: list[tuple[str, float, str]] = []
    for key, unit in MEASUREMENT_UNITS.items():
        raw = payload.get(key)
        if isinstance(raw, dict):
            raw = raw.get("value")
        if isinstance(raw, bool) or raw is None:
            continue
        if isinstance(raw, (int, float)):
            items.append((key, float(raw), unit))
            continue
        if isinstance(raw, str):
            try:
                items.append((key, float(raw.strip()), unit))
            except ValueError:
                continue
    return items
