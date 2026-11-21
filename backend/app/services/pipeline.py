"""End-to-end Milestone 3 pipeline: STT -> LLM extraction -> normalization -> validation -> risk rules."""

from __future__ import annotations

import httpx
from pydantic import BaseModel, Field

from app.core.config_loader import load_visit_config
from app.core.settings import Settings
from app.schemas.newborn_visit import Flag, NewbornVisitRecord
from app.services import extractor, risk_rules, stt_gnani, validator
from app.services.extractor import Ambiguity


class PipelineResult(BaseModel):
    """Structured pipeline output prior to follow-up generation (Milestone 4)."""

    transcript: str
    record: NewbornVisitRecord
    flags: list[Flag] = Field(default_factory=list)
    missing_required: list[str] = Field(default_factory=list)
    ambiguities: list[Ambiguity] = Field(default_factory=list)
    stt_latency_s: float | None = None
    llm_latency_s: float | None = None


async def process_transcript(
    transcript: str,
    language: str,
    visit_type: str = "newborn_home_visit",
    *,
    existing_record: NewbornVisitRecord | None = None,
    assigned_ids: set[str] | None = None,
    settings: Settings | None = None,
    client: httpx.AsyncClient | None = None,
    retry_delay_s: float = 1.0,
) -> PipelineResult:
    """Run extraction, deterministic validation, and risk rules on a transcript."""
    config = load_visit_config(visit_type)
    extraction = await extractor.extract(
        transcript,
        language,
        visit_type,
        existing_record=existing_record,
        settings=settings,
        client=client,
        retry_delay_s=retry_delay_s,
    )
    validation = validator.validate(
        extraction.record,
        config,
        assigned_ids=assigned_ids,
    )
    final_record = risk_rules.apply_risk(validation.record, config)
    return PipelineResult(
        transcript=transcript,
        record=final_record,
        flags=validation.flags,
        missing_required=validation.missing_required,
        ambiguities=extraction.ambiguities,
        llm_latency_s=extraction.latency_s,
    )


async def process_audio(
    audio: bytes,
    filename: str,
    language: str,
    visit_type: str = "newborn_home_visit",
    *,
    existing_record: NewbornVisitRecord | None = None,
    assigned_ids: set[str] | None = None,
    settings: Settings | None = None,
    client: httpx.AsyncClient | None = None,
    retry_delay_s: float = 1.0,
) -> PipelineResult:
    """Transcribe audio via Gnani Prisma and run the transcript pipeline."""
    stt = await stt_gnani.transcribe(
        audio,
        filename,
        language,
        settings=settings,
        client=client,
        retry_delay_s=retry_delay_s,
    )
    result = await process_transcript(
        stt.transcript,
        language,
        visit_type,
        existing_record=existing_record,
        assigned_ids=assigned_ids,
        settings=settings,
        client=client,
        retry_delay_s=retry_delay_s,
    )
    result.stt_latency_s = stt.latency_s
    return result
