"""Structured clinical record extraction using an LLM + deterministic normalization."""

from __future__ import annotations

import json
import re
from functools import lru_cache
from pathlib import Path
from typing import Generic, TypeVar

import httpx
from pydantic import BaseModel, ConfigDict, Field, ValidationError, field_validator

from app.core.errors import ApiError
from app.core.settings import Settings
from app.schemas.newborn_visit import (
    Breastfeeding,
    CordStatus,
    DangerSign,
    ExtractedField,
    FieldSource,
    LimbAbnormality,
    LimbLocation,
    NewbornVisitRecord,
)
from app.services.llm_client import generate_json
from app.services.normalize import (
    parse_digit_sequence,
    parse_number,
    parse_temperature_c,
    parse_weight_kg,
)

LOW_CONFIDENCE_THRESHOLD = 0.75

_PROMPT_PATH = Path(__file__).resolve().parent.parent / "prompts" / "extractor.md"
_FENCE_RE = re.compile(r"^\s*```(?:json)?\s*\n?(.*?)\n?\s*```\s*$", re.DOTALL | re.IGNORECASE)
_CONFIDENCE_WORDS = {"low": 0.5, "med": 0.75, "medium": 0.75, "high": 0.9}

T = TypeVar("T")


class Ambiguity(BaseModel):
    """Ambiguous or unclear item surfaced by extraction or normalization."""

    field: str
    reason: str


class ExtractionResult(BaseModel):
    """Normalized partial NewbornVisitRecord plus extracted ambiguities."""

    record: NewbornVisitRecord
    ambiguities: list[Ambiguity] = Field(default_factory=list)
    model: str | None = None
    latency_s: float | None = None


class RawField(BaseModel, Generic[T]):
    """Raw LLM field output before deterministic normalization."""

    model_config = ConfigDict(extra="ignore")

    value: T | None = None
    confidence: float = Field(default=0.8, ge=0.0, le=1.0)

    @field_validator("confidence", mode="before")
    @classmethod
    def _coerce_confidence(cls, value: object) -> object:
        if value is None:
            return 0.8
        if isinstance(value, str):
            mapped = _CONFIDENCE_WORDS.get(value.strip().lower())
            if mapped is not None:
                return mapped
        return value


class RawLimbAbnormality(BaseModel):
    """Raw limb abnormality structure returned by the LLM."""

    model_config = ConfigDict(extra="ignore")

    present: bool
    location: LimbLocation | None = None
    description: str | None = None


class RawExtractionPayload(BaseModel):
    """Raw JSON schema expected from the LLM extractor (extra keys ignored)."""

    model_config = ConfigDict(extra="ignore")

    beneficiary_id: RawField[str | int] | None = None
    baby_weight_kg: RawField[float | int | str] | None = None
    temperature_c: RawField[float | int | str] | None = None
    breastfeeding: RawField[Breastfeeding] | None = None
    cord_status: RawField[CordStatus] | None = None
    jaundice: RawField[bool] | None = None
    breathing_rate_per_min: RawField[int | float | str] | None = None
    limb_abnormality: RawField[RawLimbAbnormality] | None = None
    danger_signs: RawField[list[DangerSign]] | None = None
    mother_notes: RawField[str] | None = None
    notes: RawField[str] | None = None
    ambiguities: list[Ambiguity] = Field(default_factory=list)


@lru_cache(maxsize=1)
def _load_extractor_prompt() -> str:
    return _PROMPT_PATH.read_text(encoding="utf-8").strip()


def _strip_code_fences(text: str) -> str:
    stripped = text.strip()
    match = _FENCE_RE.match(stripped)
    return match.group(1).strip() if match else stripped


def _wrap_field(value: T | None, confidence: float) -> ExtractedField[T] | None:
    if value is None:
        return None
    return ExtractedField(
        value=value,
        confidence=confidence,
        source=FieldSource.speech,
        needs_confirmation=confidence < LOW_CONFIDENCE_THRESHOLD,
    )


def _filled_field_names(record: NewbornVisitRecord | None) -> list[str]:
    if record is None:
        return []
    names: list[str] = []
    for field_name in RawExtractionPayload.model_fields:
        if field_name == "ambiguities":
            continue
        field_obj = getattr(record, field_name, None)
        if field_obj is not None and field_obj.value is not None:
            names.append(field_name)
    return names


def _build_user_prompt(
    transcript: str,
    language: str,
    visit_type: str,
    filled_fields: list[str],
) -> str:
    schema_json = json.dumps(RawExtractionPayload.model_json_schema(), ensure_ascii=False)
    filled_json = json.dumps(filled_fields)
    return (
        f"language: {language}\n"
        f"visit_type: {visit_type}\n"
        f"already_filled_fields: {filled_json}\n"
        f"json_schema: {schema_json}\n\n"
        f"transcript:\n{transcript}"
    )


def _normalize_raw(raw: RawExtractionPayload) -> tuple[NewbornVisitRecord, list[Ambiguity]]:
    ambiguities = list(raw.ambiguities)

    def _has_ambiguity(prefixes: tuple[str, ...]) -> bool:
        return any(item.field in prefixes for item in ambiguities)

    # beneficiary_id
    beneficiary_field: ExtractedField[str] | None = None
    if raw.beneficiary_id is not None and raw.beneficiary_id.value is not None:
        raw_id = raw.beneficiary_id.value
        norm_id: str | None = None
        if isinstance(raw_id, int) and not isinstance(raw_id, bool):
            norm_id = str(raw_id)
        elif isinstance(raw_id, str):
            seq = parse_digit_sequence(raw_id)
            norm_id = seq if seq else (raw_id.strip() or None)
        beneficiary_field = _wrap_field(norm_id, raw.beneficiary_id.confidence)

    # baby_weight_kg
    weight_field: ExtractedField[float] | None = None
    if raw.baby_weight_kg is not None and raw.baby_weight_kg.value is not None:
        raw_wt = raw.baby_weight_kg.value
        norm_wt: float | None = None
        if isinstance(raw_wt, (int, float)) and not isinstance(raw_wt, bool):
            norm_wt = float(raw_wt)
        elif isinstance(raw_wt, str):
            norm_wt = parse_weight_kg(raw_wt)
            if norm_wt is None:
                ambiguities.append(
                    Ambiguity(field="baby_weight_kg", reason="Unparseable spoken weight")
                )
        weight_field = _wrap_field(norm_wt, raw.baby_weight_kg.confidence)

    # temperature_c
    temp_field: ExtractedField[float] | None = None
    if raw.temperature_c is not None and raw.temperature_c.value is not None:
        raw_temp = raw.temperature_c.value
        norm_temp: float | None = None
        if isinstance(raw_temp, (int, float)) and not isinstance(raw_temp, bool):
            norm_temp = round(float(raw_temp), 1)
        elif isinstance(raw_temp, str):
            parsed_temp = parse_temperature_c(raw_temp)
            if parsed_temp is None:
                ambiguities.append(
                    Ambiguity(field="temperature_c", reason="Unparseable spoken temperature")
                )
            else:
                norm_temp = parsed_temp[0]
        temp_field = _wrap_field(norm_temp, raw.temperature_c.confidence)

    # breathing_rate_per_min
    breathing_field: ExtractedField[int] | None = None
    if raw.breathing_rate_per_min is not None and raw.breathing_rate_per_min.value is not None:
        raw_br = raw.breathing_rate_per_min.value
        norm_br: int | None = None
        if isinstance(raw_br, int) and not isinstance(raw_br, bool):
            norm_br = raw_br
        elif isinstance(raw_br, float):
            norm_br = int(round(raw_br))
        elif isinstance(raw_br, str):
            parsed_num = parse_number(raw_br)
            if parsed_num is None:
                ambiguities.append(
                    Ambiguity(
                        field="breathing_rate_per_min",
                        reason="Unparseable spoken breathing rate",
                    )
                )
            else:
                norm_br = int(round(parsed_num))
        breathing_field = _wrap_field(norm_br, raw.breathing_rate_per_min.confidence)

    # limb_abnormality
    limb_field: ExtractedField[LimbAbnormality] | None = None
    if raw.limb_abnormality is not None and raw.limb_abnormality.value is not None:
        raw_limb = raw.limb_abnormality.value
        loc = raw_limb.location
        if raw_limb.present and loc in (None, LimbLocation.unspecified):
            loc = LimbLocation.unspecified
            if not _has_ambiguity(("limb_abnormality", "limb_abnormality.location")):
                ambiguities.append(
                    Ambiguity(
                        field="limb_abnormality.location",
                        reason="Limb abnormality present but affected limb not specified",
                    )
                )
        limb_val = LimbAbnormality(
            present=raw_limb.present,
            location=loc,
            description=raw_limb.description,
        )
        limb_field = _wrap_field(limb_val, raw.limb_abnormality.confidence)

    record = NewbornVisitRecord(
        beneficiary_id=beneficiary_field,
        baby_weight_kg=weight_field,
        temperature_c=temp_field,
        breastfeeding=_wrap_field(
            raw.breastfeeding.value if raw.breastfeeding else None,
            raw.breastfeeding.confidence if raw.breastfeeding else 0.8,
        ),
        cord_status=_wrap_field(
            raw.cord_status.value if raw.cord_status else None,
            raw.cord_status.confidence if raw.cord_status else 0.8,
        ),
        jaundice=_wrap_field(
            raw.jaundice.value if raw.jaundice else None,
            raw.jaundice.confidence if raw.jaundice else 0.8,
        ),
        breathing_rate_per_min=breathing_field,
        limb_abnormality=limb_field,
        danger_signs=_wrap_field(
            raw.danger_signs.value if raw.danger_signs else None,
            raw.danger_signs.confidence if raw.danger_signs else 0.8,
        ),
        mother_notes=_wrap_field(
            raw.mother_notes.value.strip() if raw.mother_notes and raw.mother_notes.value else None,
            raw.mother_notes.confidence if raw.mother_notes else 0.8,
        ),
        notes=_wrap_field(
            raw.notes.value.strip() if raw.notes and raw.notes.value else None,
            raw.notes.confidence if raw.notes else 0.8,
        ),
    )
    return record, ambiguities


def _is_protected(current: ExtractedField | None, incoming: ExtractedField) -> bool:
    return (
        current is not None
        and current.value is not None
        and current.source in (FieldSource.selected, FieldSource.typed)
        and incoming.source == FieldSource.speech
    )


def merge_records(
    base: NewbornVisitRecord | None,
    update: NewbornVisitRecord,
) -> NewbornVisitRecord:
    """Merge an extracted partial record onto an existing NewbornVisitRecord."""
    if base is None:
        return update.model_copy(deep=True)

    merged = base.model_copy(deep=True)
    if merged.visit_date is None and update.visit_date is not None:
        merged.visit_date = update.visit_date

    scalar_fields = (
        "beneficiary_id",
        "baby_weight_kg",
        "temperature_c",
        "breastfeeding",
        "cord_status",
        "jaundice",
        "breathing_rate_per_min",
    )
    for field_name in scalar_fields:
        incoming = getattr(update, field_name)
        if incoming is None or incoming.value is None:
            continue
        current = getattr(merged, field_name)
        if _is_protected(current, incoming):
            continue
        setattr(merged, field_name, incoming.model_copy(deep=True))

    # Limb abnormality: refine unspecified location/description when present=True
    if update.limb_abnormality is not None and update.limb_abnormality.value is not None:
        inc_limb = update.limb_abnormality
        cur_limb = merged.limb_abnormality
        if cur_limb is None or cur_limb.value is None:
            merged.limb_abnormality = inc_limb.model_copy(deep=True)
        elif not _is_protected(cur_limb, inc_limb):
            cur_val = cur_limb.value
            inc_val = inc_limb.value
            if cur_val.present and inc_val.present:
                location = (
                    inc_val.location
                    if inc_val.location not in (None, LimbLocation.unspecified)
                    else cur_val.location
                )
                description = inc_val.description or cur_val.description
                merged.limb_abnormality = ExtractedField(
                    value=LimbAbnormality(
                        present=True,
                        location=location,
                        description=description,
                    ),
                    confidence=inc_limb.confidence,
                    source=inc_limb.source,
                    needs_confirmation=inc_limb.needs_confirmation,
                )
            else:
                merged.limb_abnormality = inc_limb.model_copy(deep=True)

    # Danger signs: ordered unique union
    if update.danger_signs is not None and update.danger_signs.value:
        inc_ds = update.danger_signs
        cur_ds = merged.danger_signs
        if cur_ds is None or not cur_ds.value:
            merged.danger_signs = inc_ds.model_copy(deep=True)
        elif not _is_protected(cur_ds, inc_ds):
            combined = list(cur_ds.value)
            for sign in inc_ds.value:
                if sign not in combined:
                    combined.append(sign)
            merged.danger_signs = ExtractedField(
                value=combined,
                confidence=min(cur_ds.confidence, inc_ds.confidence),
                source=inc_ds.source,
                needs_confirmation=cur_ds.needs_confirmation or inc_ds.needs_confirmation,
            )

    # Free-text notes: append distinct values
    for text_field in ("mother_notes", "notes"):
        inc_txt = getattr(update, text_field)
        if inc_txt is None or not inc_txt.value:
            continue
        cur_txt = getattr(merged, text_field)
        if cur_txt is None or not cur_txt.value:
            setattr(merged, text_field, inc_txt.model_copy(deep=True))
        elif not _is_protected(cur_txt, inc_txt):
            inc_clean = inc_txt.value.strip()
            if inc_clean and inc_clean not in cur_txt.value:
                cur_txt.value = f"{cur_txt.value}; {inc_clean}"

    return merged


async def extract(
    transcript: str,
    language: str,
    visit_type: str = "newborn_home_visit",
    *,
    existing_record: NewbornVisitRecord | None = None,
    settings: Settings | None = None,
    client: httpx.AsyncClient | None = None,
    retry_delay_s: float = 1.0,
) -> ExtractionResult:
    """Extract and deterministically normalize a partial NewbornVisitRecord from transcript."""
    if not transcript or not transcript.strip():
        base = existing_record.model_copy(deep=True) if existing_record else NewbornVisitRecord()
        return ExtractionResult(record=base, ambiguities=[])

    system_prompt = _load_extractor_prompt()
    filled_fields = _filled_field_names(existing_record)
    user_prompt = _build_user_prompt(transcript, language, visit_type, filled_fields)

    total_latency = 0.0
    model_used: str | None = None
    raw_payload: RawExtractionPayload | None = None

    for attempt in range(2):
        prompt_to_send = (
            user_prompt
            if attempt == 0
            else (
                f"{user_prompt}\n\n"
                "Your previous reply was not valid JSON matching the schema. "
                "Return ONLY valid JSON matching the schema."
            )
        )
        llm_resp = await generate_json(
            system_prompt,
            prompt_to_send,
            settings=settings,
            client=client,
            retry_delay_s=retry_delay_s,
        )
        total_latency += llm_resp.latency_s
        model_used = llm_resp.model

        cleaned = _strip_code_fences(llm_resp.text)
        try:
            parsed = json.loads(cleaned)
            raw_payload = RawExtractionPayload.model_validate(parsed)
            break
        except (json.JSONDecodeError, ValidationError) as exc:
            if attempt == 0:
                continue
            raise ApiError(
                "LLM_PARSE_FAILED",
                "Could not understand the structured record. Please repeat.",
                502,
            ) from exc

    assert raw_payload is not None
    partial_record, ambiguities = _normalize_raw(raw_payload)
    merged = merge_records(existing_record, partial_record)
    return ExtractionResult(
        record=merged,
        ambiguities=ambiguities,
        model=model_used,
        latency_s=round(total_latency, 3),
    )
