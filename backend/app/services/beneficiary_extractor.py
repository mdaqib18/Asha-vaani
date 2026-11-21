"""Multilingual deterministic extractor for Speak-to-Add beneficiary utterances (SPEC_V2 §3.4)."""

from __future__ import annotations

import re
from dataclasses import dataclass
from datetime import date, timedelta

from app.services.due_engine import compute_edd

_DIGIT_TRANSLATION = str.maketrans(
    "०१२३४५६७८९೦೧೨೩೪೫೬೭೮೯",
    "01234567890123456789",
)


@dataclass(frozen=True)
class BeneficiarySpeechDraft:
    """Editable beneficiary draft parsed from spoken transcript."""

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


_INTRO_RE = re.compile(
    r"^\s*(?:naya beneficiary|new beneficiary|add beneficiary|beneficiary|"
    r"नया लाभार्थी|नई लाभार्थी|लाभार्थी|ಹೊಸ ಫಲಾನುಭವಿ|ಫಲಾನುಭವಿ)\s*[,:\-–]?\s*",
    flags=re.IGNORECASE,
)

_AGE_YEARS_RE = re.compile(
    r"\b(\d{1,3})\s*(?:years?\s*(?:old)?|yrs?|saal|sal|baras|साल|वर्ष|ವರ್ಷ(?:ದ)?)\b",
    flags=re.IGNORECASE,
)
_AGE_MONTHS_CHILD_RE = re.compile(
    r"\b(\d{1,2})\s*(?:months?\s*old|mahine\s*ka|mahine\s*ki)\b",
    flags=re.IGNORECASE,
)
_AGE_DAYS_RE = re.compile(
    r"\b(\d{1,3})\s*(?:days?\s*(?:old)?|din|दिन|ದಿನ(?:ದ)?)\b",
    flags=re.IGNORECASE,
)
_PREG_MONTHS_RE = re.compile(
    r"\b(\d{1,2})\s*(?:months?|mahine|mahina|maah|महीने|महीना|माह|ತಿಂಗಳು)\b",
    flags=re.IGNORECASE,
)
_PHONE_RE = re.compile(r"(?:\+?91[\s\-]?)?([6-9]\d{4}[\s\-]?\d{5})\b")

_PREGNANT_RE = re.compile(
    r"\b(?:pregnant|pregnancy|anc|garbhavati)\b|गर्भवती|ಗರ್ಭಿಣಿ",
    flags=re.IGNORECASE,
)
_NEWBORN_RE = re.compile(
    r"\b(?:newborn|new\s*born|navjat|baby\s+of|infant|neonate)\b|नवजात|ನವಜಾತ",
    flags=re.IGNORECASE,
)
_CHILD_RE = re.compile(
    r"\b(?:child|toddler|bacha|baccha|bachi)\b|बच्चा|बच्ची|ಮಗು",
    flags=re.IGNORECASE,
)
_FEMALE_RE = re.compile(
    r"\b(?:female|woman|lady|girl|mother|mahila|aurat|ladki|pregnant)\b|"
    r"महिला|लड़की|गर्भवती|ಮಹಿಳೆ|ಹೆಣ್ಣು|ಗರ್ಭಿಣಿ",
    flags=re.IGNORECASE,
)
_MALE_RE = re.compile(
    r"\b(?:male|man|boy|ladka)\b|पुरुष|लड़का|ಗಂಡು",
    flags=re.IGNORECASE,
)


def mask_phone(phone: str | None) -> str | None:
    """Return UI-safe masked phone string preserving only trailing 4 digits."""
    if not phone:
        return None
    digits = re.sub(r"\D", "", phone)
    if len(digits) < 4:
        return "••••"
    last4 = digits[-4:]
    stars = "•" * max(4, min(6, len(digits) - 4))
    return f"{stars}{last4}"


def _subtract_years(ref: date, years: int) -> date:
    try:
        return ref.replace(year=ref.year - years)
    except ValueError:
        # Handle Feb 29 cleanly.
        return ref.replace(year=ref.year - years, day=28)


def _extract_area_and_name(cleaned_text: str) -> tuple[str, str | None]:
    chunks = [c.strip() for c in cleaned_text.split(",") if c.strip()]
    area_note: str | None = None
    name = ""

    # explicit "village Rampur" / "area Rampur" / "gaon Rampur"
    explicit_area = re.search(
        r"\b(?:village|area|gaon|gram|ward|mohalla|ग्राम|गांव|ಏರಿಯಾ)\s+([a-zA-Z\u0900-\u097F\u0C80-\u0CFF][a-zA-Z0-9\s\-]{1,40})",
        cleaned_text,
        flags=re.IGNORECASE,
    )
    if explicit_area:
        area_note = explicit_area.group(1).strip(" ,.")

    status_or_meta_re = re.compile(
        r"(?:\d|\b(?:years?|yrs?|saal|sal|days?|din|months?|mahine|mahina|"
        r"pregnant|pregnancy|garbhavati|newborn|navjat|child|male|female|boy|girl|old|anc)\b)",
        flags=re.IGNORECASE,
    )

    candidate_chunks: list[str] = []
    for chunk in chunks:
        # Strip explicit prefixes
        c = re.sub(r"^(?:naam|name(?:\s+is)?)\s+", "", chunk, flags=re.IGNORECASE).strip()
        if not status_or_meta_re.search(c) and len(c) >= 2:
            candidate_chunks.append(c)

    if candidate_chunks:
        name = candidate_chunks[0]
        if area_note is None and len(candidate_chunks) >= 2:
            area_note = candidate_chunks[-1]
    elif chunks:
        # Take leading alphabetic words from first chunk before numbers/status words.
        first = chunks[0]
        first = re.sub(r"^(?:newborn|child|pregnant|woman)\s+", "", first, flags=re.IGNORECASE)
        first = re.split(
            r"\s+(?:\d|pregnant|newborn|child|male|female|boy|girl|village|area)\b",
            first,
            maxsplit=1,
            flags=re.IGNORECASE,
        )[0]
        name = first.strip(" ,.")

    # Normalize casing cleanly for Baby of X / plain ASCII names
    name = re.sub(r"^(?:newborn\s+)", "", name, flags=re.IGNORECASE).strip()
    if re.match(r"^baby\s+of\s+", name, flags=re.IGNORECASE):
        suffix = name[len("baby of ") :].strip()
        name = f"Baby of {suffix.title() if suffix.isascii() else suffix}"
    elif name.isascii() and name.islower():
        name = name.title()

    return name, area_note


def extract_beneficiary_from_transcript(
    transcript: str,
    *,
    today: date | None = None,
) -> BeneficiarySpeechDraft:
    """Parse structured beneficiary registration fields from speech transcript."""
    ref_today = today or date.today()
    normalized = re.sub(
        r"\s+",
        " ",
        (transcript or "").translate(_DIGIT_TRANSLATION),
    ).strip()
    cleaned = _INTRO_RE.sub("", normalized).strip()

    phone: str | None = None
    phone_match = _PHONE_RE.search(cleaned)
    if phone_match:
        phone = re.sub(r"\D", "", phone_match.group(1))
        cleaned_no_phone = cleaned[: phone_match.start()] + cleaned[phone_match.end() :]
    else:
        cleaned_no_phone = cleaned

    age_years: int | None = None
    age_days: int | None = None
    dob: str | None = None
    dob_is_estimated = False
    pregnancy_months: int | None = None
    lmp_date: str | None = None
    edd_date: str | None = None

    is_pregnant = bool(_PREGNANT_RE.search(cleaned_no_phone))
    is_newborn_kw = bool(_NEWBORN_RE.search(cleaned_no_phone))
    is_child_kw = bool(_CHILD_RE.search(cleaned_no_phone))

    days_m = _AGE_DAYS_RE.search(cleaned_no_phone)
    years_m = _AGE_YEARS_RE.search(cleaned_no_phone)

    if days_m:
        age_days = int(days_m.group(1))
        dob = (ref_today - timedelta(days=age_days)).isoformat()
        dob_is_estimated = True
    elif years_m:
        age_years = int(years_m.group(1))
        dob = _subtract_years(ref_today, age_years).isoformat()
        dob_is_estimated = True

    if is_pregnant:
        beneficiary_type = "pregnant_woman"
        preg_m = _PREG_MONTHS_RE.search(cleaned_no_phone)
        if preg_m:
            months = int(preg_m.group(1))
            if 1 <= months <= 10:
                pregnancy_months = months
                lmp = ref_today - timedelta(days=months * 30)
                lmp_date = lmp.isoformat()
                edd_date = compute_edd(lmp).isoformat()
    elif is_newborn_kw or (age_days is not None and age_days <= 42):
        beneficiary_type = "newborn"
    elif is_child_kw or _AGE_MONTHS_CHILD_RE.search(cleaned_no_phone) or (
        age_years is not None and age_years < 5
    ):
        beneficiary_type = "child_u5"
    elif age_years is not None and age_years >= 18:
        beneficiary_type = "adult"
    else:
        beneficiary_type = "other"

    if _FEMALE_RE.search(cleaned_no_phone):
        sex = "female"
    elif _MALE_RE.search(cleaned_no_phone):
        sex = "male"
    else:
        sex = "unknown"

    full_name, area_note = _extract_area_and_name(cleaned_no_phone)

    return BeneficiarySpeechDraft(
        full_name=full_name,
        beneficiary_type=beneficiary_type,
        sex=sex,
        dob=dob,
        dob_is_estimated=dob_is_estimated,
        age_years=age_years,
        age_days=age_days,
        pregnancy_months=pregnancy_months,
        lmp_date=lmp_date,
        edd_date=edd_date,
        area_note=area_note,
        phone=phone,
    )
