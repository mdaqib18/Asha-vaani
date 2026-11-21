"""Follow-up decision engine and read-back confirmation text builder (SPEC §8.4 & §8.5)."""

from __future__ import annotations

import json
import re
from functools import lru_cache
from pathlib import Path
from typing import Literal

import httpx
from pydantic import BaseModel, Field

from app.core.errors import ApiError
from app.core.settings import Settings
from app.schemas.newborn_visit import LimbLocation, NewbornVisitRecord
from app.services.extractor import Ambiguity
from app.services.llm_client import generate_json

_PROMPT_PATH = Path(__file__).resolve().parent.parent / "prompts" / "followup.md"
_FENCE_RE = re.compile(r"^\s*```(?:json)?\s*\n?(.*?)\n?\s*```\s*$", re.DOTALL | re.IGNORECASE)

FIELD_LABELS: dict[str, dict[str, str]] = {
    "en": {
        "beneficiary_id": "beneficiary ID",
        "baby_weight_kg": "baby weight",
        "temperature_c": "temperature",
        "breastfeeding": "breastfeeding status",
        "cord_status": "cord status",
        "jaundice": "jaundice check",
        "limb_abnormality": "limb check",
    },
    "hi": {
        "beneficiary_id": "लाभार्थी नंबर",
        "baby_weight_kg": "बच्चे का वजन",
        "temperature_c": "तापमान",
        "breastfeeding": "स्तनपान की जानकारी",
        "cord_status": "नाल की स्थिति",
        "jaundice": "पीलिया की जांच",
        "limb_abnormality": "हाथ-पैर की जांच",
    },
    "kn": {
        "beneficiary_id": "ಫಲಾನುಭವಿ ಸಂಖ್ಯೆ",
        "baby_weight_kg": "ಮಗುವಿನ ತೂಕ",
        "temperature_c": "ತಾಪಮಾನ",
        "breastfeeding": "ಸ್ತನ್ಯಪಾನದ ವಿವರ",
        "cord_status": "ಹೊಕ್ಕಳುಬಳ್ಳಿಯ ಸ್ಥಿತಿ",
        "jaundice": "ಕಾಮಾಲೆ ತಪಾಸಣೆ",
        "limb_abnormality": "ಕೈ-ಕಾಲುಗಳ ತಪಾಸಣೆ",
    },
}


class FollowupPayload(BaseModel):
    """Follow-up question payload returned to the mobile app."""

    question_text: str
    question_audio_url: str | None = None
    target_fields: list[str]
    followup_count: int


class FollowupDecision(BaseModel):
    """Internal decision returned by the follow-up engine."""

    status: Literal["needs_followup", "ready_to_confirm", "error_retry"]
    question_text: str | None = None
    target_fields: list[str] = Field(default_factory=list)
    followup_count: int
    source: Literal["missing_required", "llm_ambiguity", "ambiguity_fallback", "none"] = "none"


@lru_cache(maxsize=1)
def _load_followup_prompt() -> str:
    return _PROMPT_PATH.read_text(encoding="utf-8").strip()


def _join_labels(labels: list[str], language: str) -> str:
    if len(labels) <= 1:
        return labels[0] if labels else ""
    conj = {"hi": " और ", "kn": " ಮತ್ತು "}.get(language, " and ")
    return f"{', '.join(labels[:-1])}{conj}{labels[-1]}"


def build_missing_fields_question(fields: list[str], language: str) -> str:
    """Build one combined localized question for missing required fields."""
    lang = language if language in FIELD_LABELS else "en"
    label_map = FIELD_LABELS[lang]
    labels = [label_map.get(field, field.replace("_", " ")) for field in fields]
    joined = _join_labels(labels, lang)
    if lang == "hi":
        return f"{joined} की जानकारी बाकी है। कृपया बताइए।"
    if lang == "kn":
        return f"{joined} ವಿವರಗಳು ಬಾಕಿ ಇವೆ. ದಯವಿಟ್ಟು ತಿಳಿಸಿ."
    return f"{joined} details are missing. Please tell me."


def filter_unresolved_ambiguities(
    record: NewbornVisitRecord,
    ambiguities: list[Ambiguity],
    asked_fields: set[str],
) -> list[Ambiguity]:
    """Keep only ambiguities that have not been asked yet and are still unresolved."""
    unresolved: list[Ambiguity] = []
    seen_fields: set[str] = set()

    for amb in ambiguities:
        if amb.field in seen_fields or amb.field in asked_fields:
            continue
        base_field = amb.field.split(".", 1)[0]
        if base_field in asked_fields:
            continue

        if amb.field in ("limb_abnormality", "limb_abnormality.location"):
            if "limb_abnormality" in asked_fields or "limb_abnormality.location" in asked_fields:
                continue
            limb = record.limb_abnormality
            if (
                limb is None
                or limb.value is None
                or not limb.value.present
                or limb.value.location not in (None, LimbLocation.unspecified)
            ):
                continue
        elif hasattr(record, base_field):
            field_obj = getattr(record, base_field)
            if field_obj is not None and getattr(field_obj, "value", None) is not None:
                continue

        seen_fields.add(amb.field)
        unresolved.append(amb)

    return unresolved


def _fallback_ambiguity_question(ambiguities: list[Ambiguity], language: str) -> str:
    lang = language if language in FIELD_LABELS else "en"
    if any(a.field in ("limb_abnormality", "limb_abnormality.location") for a in ambiguities):
        if lang == "hi":
            return "कृपया बताइए कि बच्चे के किस हाथ या पैर में समस्या है?"
        if lang == "kn":
            return "ದಯವಿಟ್ಟು ಮಗುವಿನ ಯಾವ ಕೈ ಅಥವಾ ಕಾಲಿನಲ್ಲಿ ಸಮಸ್ಯೆ ಇದೆ ಎಂದು ತಿಳಿಸಿ?"
        return "Which limb is affected?"

    label_map = FIELD_LABELS[lang]
    labels = [label_map.get(a.field.split(".", 1)[0], a.field) for a in ambiguities]
    joined = _join_labels(labels, lang)
    if lang == "hi":
        return f"कृपया {joined} के बारे में साफ जानकारी दें।"
    if lang == "kn":
        return f"ದಯವಿಟ್ಟು {joined} ಬಗ್ಗೆ ಸ್ಪಷ್ಟ ವಿವರ ತಿಳಿಸಿ."
    return f"Please clarify the details for {joined}."


def _filled_field_names(record: NewbornVisitRecord) -> list[str]:
    filled: list[str] = []
    for name in (
        "beneficiary_id",
        "baby_weight_kg",
        "temperature_c",
        "breastfeeding",
        "cord_status",
        "jaundice",
        "breathing_rate_per_min",
        "limb_abnormality",
        "danger_signs",
        "mother_notes",
        "notes",
    ):
        obj = getattr(record, name, None)
        if obj is not None and obj.value is not None:
            filled.append(name)
    return filled


def _parse_question_json(text: str) -> str:
    stripped = text.strip()
    match = _FENCE_RE.match(stripped)
    cleaned = match.group(1).strip() if match else stripped
    parsed = json.loads(cleaned)
    if not isinstance(parsed, dict):
        raise ValueError("Expected JSON object")
    q = parsed.get("question_text")
    if not isinstance(q, str) or not q.strip():
        raise ValueError("Missing question_text")
    return q.strip()


async def decide_followup(
    record: NewbornVisitRecord,
    missing_required: list[str],
    ambiguities: list[Ambiguity],
    *,
    language: str,
    followup_count: int,
    max_followups: int = 2,
    asked_fields: set[str] | None = None,
    settings: Settings | None = None,
    client: httpx.AsyncClient | None = None,
    retry_delay_s: float = 1.0,
) -> FollowupDecision:
    """Decide whether to ask a missing-fields or ambiguity follow-up, or move to confirm."""
    if followup_count >= max_followups:
        return FollowupDecision(
            status="ready_to_confirm",
            followup_count=followup_count,
            source="none",
        )

    asked = set(asked_fields or set())

    # 1. Deterministic missing required fields first.
    unasked_missing = [field for field in missing_required if field not in asked]
    if unasked_missing:
        question = build_missing_fields_question(unasked_missing, language)
        return FollowupDecision(
            status="needs_followup",
            question_text=question,
            target_fields=unasked_missing,
            followup_count=followup_count + 1,
            source="missing_required",
        )

    # 2. LLM ambiguity follow-up second.
    unresolved = filter_unresolved_ambiguities(record, ambiguities, asked)
    if unresolved:
        target_fields = [a.field for a in unresolved]
        system_prompt = _load_followup_prompt()
        user_prompt = (
            f"language: {language}\n"
            f"already_filled_fields: {json.dumps(_filled_field_names(record))}\n"
            f"ambiguities: {json.dumps([a.model_dump() for a in unresolved], ensure_ascii=False)}"
        )
        try:
            llm_resp = await generate_json(
                system_prompt,
                user_prompt,
                settings=settings,
                client=client,
                retry_delay_s=retry_delay_s,
            )
            question = _parse_question_json(llm_resp.text)
            source: Literal["llm_ambiguity", "ambiguity_fallback"] = "llm_ambiguity"
        except (ApiError, json.JSONDecodeError, ValueError, TypeError):
            question = _fallback_ambiguity_question(unresolved, language)
            source = "ambiguity_fallback"

        return FollowupDecision(
            status="needs_followup",
            question_text=question,
            target_fields=target_fields,
            followup_count=followup_count + 1,
            source=source,
        )

    return FollowupDecision(
        status="ready_to_confirm",
        followup_count=followup_count,
        source="none",
    )


def build_readback_text(record: NewbornVisitRecord, language: str) -> str:
    """Build spoken read-back confirmation text for key fields (ID, weight, temperature)."""
    lang = language if language in FIELD_LABELS else "en"
    missing_word = {
        "en": "not recorded",
        "hi": "दर्ज नहीं है",
        "kn": "ದಾಖಲಾಗಿಲ್ಲ",
    }[lang]

    bid = (
        record.beneficiary_id.value
        if record.beneficiary_id and record.beneficiary_id.value is not None
        else missing_word
    )
    wt_unit = {"en": " kg", "hi": " किलो", "kn": " ಕೆಜಿ"}[lang]
    wt = (
        f"{record.baby_weight_kg.value}{wt_unit}"
        if record.baby_weight_kg and record.baby_weight_kg.value is not None
        else missing_word
    )
    temp_unit = {"en": " degrees Celsius", "hi": " डिग्री सेल्सियस", "kn": " ಡಿಗ್ರಿ ಸೆಲ್ಸಿಯಸ್"}[lang]
    temp = (
        f"{record.temperature_c.value}{temp_unit}"
        if record.temperature_c and record.temperature_c.value is not None
        else missing_word
    )

    if lang == "hi":
        return f"कृपया जांचें। लाभार्थी नंबर {bid}, वजन {wt}, तापमान {temp}।"
    if lang == "kn":
        return f"ದಯವಿಟ್ಟು ಖಚಿತಪಡಿಸಿ. ಫಲಾನುಭವಿ ಸಂಖ್ಯೆ {bid}, ತೂಕ {wt}, ತಾಪಮಾನ {temp}."
    return f"Please confirm. Beneficiary ID {bid}, weight {wt}, temperature {temp}."
