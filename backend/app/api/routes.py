from __future__ import annotations

import base64
import binascii
import json
import secrets
import uuid
from datetime import date, timedelta

import httpx
from fastapi import APIRouter, Depends, File, Form, Query, Response, UploadFile

from app.core.config_loader import VisitTypeConfig, list_visit_configs, load_visit_config
from app.core.errors import ApiError
from app.core.settings import Settings, get_settings
from app.data.beneficiaries import (
    get_assigned_ids,
    verify_worker_credentials,
)
from app.db.models import Beneficiary as V2Beneficiary
from app.db.repository import V2Repository, get_v2_repository
from app.db.store import StoredSession, VisitStore, get_store
from app.schemas.api import (
    BeneficiaryCreateRequest,
    BeneficiaryFromAudioResponse,
    BeneficiaryOut,
    BeneficiaryPatchRequest,
    BeneficiarySpeechDraftOut,
    BeneficiaryVisitsResponse,
    ConfirmResponse,
    DetectedPurposeOut,
    DuplicateCandidateOut,
    DuplicateCheckRequest,
    LoginRequest,
    LoginResponse,
    MeasurementPointOut,
    ReadbackResponse,
    RecordPatchRequest,
    RecordPatchResponse,
    SuggestedPurposeResponse,
    SyncItemRequest,
    SyncItemResult,
    SyncResponse,
    VisitSummary,
    VisitTurnResponse,
    VisitTypeFieldOut,
    VisitTypeOut,
    WorkerProfile,
)
from app.schemas.newborn_visit import ExtractedField, FieldSource
from app.services import risk_rules, stt_gnani, tts_gnani, validator
from app.services.beneficiary_extractor import (
    extract_beneficiary_from_transcript,
    mask_phone,
)
from app.services.followup import (
    FollowupPayload,
    build_readback_text,
    decide_followup,
    filter_unresolved_ambiguities,
)
from app.services.gnani_common import LANGUAGE_MAP
from app.services.measurements import extract_numeric_measurements
from app.services.pipeline import process_audio
from app.services.purpose_engine import suggest_visit_purpose
from app.services.tts_gnani import TTS_CONTENT_TYPE

router = APIRouter(prefix="/v1")


def get_http_client() -> httpx.AsyncClient | None:
    """FastAPI dependency for optional shared HTTP client (overridable in tests)."""
    return None


def _validate_language(language: str) -> None:
    if language not in LANGUAGE_MAP:
        raise ApiError("INVALID_LANGUAGE", f"Unsupported language code: {language}", 400)


def _require_session(store: VisitStore, session_id: str) -> StoredSession:
    session = store.get_session(session_id)
    if session is None:
        raise ApiError("SESSION_NOT_FOUND", "Visit session not found.", 404)
    return session


async def _try_tts_url(
    text: str,
    language: str,
    *,
    store: VisitStore,
    settings: Settings,
    client: httpx.AsyncClient | None,
) -> str | None:
    try:
        audio_bytes = await tts_gnani.synthesize(
            text,
            language,
            settings=settings,
            client=client,
        )
    except ApiError:
        return None
    audio_id = store.save_audio(audio_bytes, TTS_CONTENT_TYPE)
    return f"/v1/audio/{audio_id}"


async def _run_visit_turn(
    session: StoredSession,
    audio_bytes: bytes,
    filename: str,
    language: str,
    *,
    store: VisitStore,
    settings: Settings,
    http_client: httpx.AsyncClient | None,
    repo: V2Repository | None = None,
) -> VisitTurnResponse:
    prev_snapshot = session.record.model_dump(mode="json")
    assigned_ids = get_assigned_ids(session.asha_id)
    if repo is not None:
        assigned_ids |= repo.list_local_codes_for_worker(session.asha_id)

    result = await process_audio(
        audio_bytes,
        filename,
        language,
        session.visit_type,
        existing_record=session.record,
        assigned_ids=assigned_ids,
        settings=settings,
        client=http_client,
    )

    cfg_schema_version = load_visit_config(session.visit_type).schema_version

    if not result.transcript.strip() and prev_snapshot == result.record.model_dump(mode="json"):
        session.status = "error_retry"
        session.language = language
        session.last_transcript = result.transcript
        store.create_or_update_session(session)
        return VisitTurnResponse(
            session_id=session.session_id,
            transcript=result.transcript,
            record=result.record,
            flags=result.flags,
            risk_flags=result.record.risk_flags,
            referral_suggested=result.record.referral_suggested,
            status="error_retry",
            followup=None,
            visit_type_code=session.visit_type,
            schema_version=cfg_schema_version,
        )

    combined_ambiguities = list(session.ambiguities)
    existing_amb_fields = {a.field for a in combined_ambiguities}
    for amb in result.ambiguities:
        if amb.field not in existing_amb_fields:
            combined_ambiguities.append(amb)
            existing_amb_fields.add(amb.field)
    unresolved_ambiguities = filter_unresolved_ambiguities(
        result.record,
        combined_ambiguities,
        set(),
    )

    decision = await decide_followup(
        result.record,
        result.missing_required,
        unresolved_ambiguities,
        language=language,
        followup_count=session.followup_count,
        max_followups=settings.MAX_FOLLOWUPS,
        asked_fields=set(session.asked_fields),
        settings=settings,
        client=http_client,
    )

    followup_payload: FollowupPayload | None = None
    if decision.status == "needs_followup" and decision.question_text:
        audio_url = await _try_tts_url(
            decision.question_text,
            language,
            store=store,
            settings=settings,
            client=http_client,
        )
        session.followup_count = decision.followup_count
        for target in decision.target_fields:
            if target not in session.asked_fields:
                session.asked_fields.append(target)
        followup_payload = FollowupPayload(
            question_text=decision.question_text,
            question_audio_url=audio_url,
            target_fields=decision.target_fields,
            followup_count=decision.followup_count,
        )

    session.record = result.record
    session.flags = result.flags
    session.ambiguities = unresolved_ambiguities
    session.status = decision.status
    session.language = language
    session.last_transcript = result.transcript
    store.create_or_update_session(session)

    return VisitTurnResponse(
        session_id=session.session_id,
        transcript=result.transcript,
        record=result.record,
        flags=result.flags,
        risk_flags=result.record.risk_flags,
        referral_suggested=result.record.referral_suggested,
        status=decision.status,
        followup=followup_payload,
        visit_type_code=session.visit_type,
        schema_version=cfg_schema_version,
    )


@router.get("/health")
def health() -> dict[str, str]:
    """Liveness check."""
    return {"status": "ok"}


def _to_visit_type_out(cfg: VisitTypeConfig) -> VisitTypeOut:
    return VisitTypeOut(
        code=cfg.effective_code,
        schema_version=cfg.schema_version,
        name=cfg.name or {"en": cfg.effective_code},
        description=cfg.description,
        applies_to=cfg.applies_to,
        required_fields=cfg.required_fields,
        fields=[VisitTypeFieldOut(**f.model_dump()) for f in cfg.fields],
        voice_keywords=cfg.voice_keywords,
        active=cfg.active,
    )


@router.get("/visit-types", response_model=list[VisitTypeOut])
def list_visit_types(
    beneficiary_type: str | None = Query(None),
) -> list[VisitTypeOut]:
    """Return active visit purpose definitions from the YAML registry (SPEC_V2 §4.1, §9)."""
    configs = list_visit_configs(active_only=True)
    if beneficiary_type:
        btype = beneficiary_type.strip().lower()
        configs = [c for c in configs if not c.applies_to or btype in c.applies_to]
    return [_to_visit_type_out(c) for c in configs]


@router.get(
    "/beneficiaries/{beneficiary_id}/suggested-purpose",
    response_model=SuggestedPurposeResponse,
)
def get_suggested_purpose(
    beneficiary_id: str,
    beneficiary_type: str | None = Query(None),
    dob: str | None = Query(None),
    last_visit_at: str | None = Query(None),
    spoken_hint: str | None = Query(None),
    repo: V2Repository = Depends(get_v2_repository),
) -> SuggestedPurposeResponse:
    """Suggest the primary visit purpose for a beneficiary plus valid alternatives."""
    stored_ben = repo.get_beneficiary_by_id_or_code(beneficiary_id)
    raw_dob = dob or (stored_ben.dob if stored_ben is not None else None)
    raw_last = last_visit_at or (stored_ben.last_visit_at if stored_ben is not None else None)
    parsed_dob: date | None = None
    parsed_last: date | None = None
    try:
        if raw_dob:
            parsed_dob = date.fromisoformat(raw_dob[:10])
        if raw_last:
            parsed_last = date.fromisoformat(raw_last[:10])
    except ValueError as exc:
        raise ApiError("INVALID_DATE", f"Invalid ISO date format: {exc}", 400) from exc

    resolved_type = (
        beneficiary_type
        or (stored_ben.beneficiary_type if stored_ben is not None else "newborn")
    ).strip().lower()
    suggestion = suggest_visit_purpose(
        beneficiary_type=resolved_type,
        dob=parsed_dob,
        last_visit_at=parsed_last,
        spoken_hint=spoken_hint,
    )
    return SuggestedPurposeResponse(
        beneficiary_id=beneficiary_id,
        suggested_code=suggestion.suggested_code,
        reason=suggestion.reason,
        other_codes=suggestion.other_codes,
        detected_purpose=(
            DetectedPurposeOut(
                code=suggestion.detected_purpose.code,
                confidence=suggestion.detected_purpose.confidence,
                matched_keyword=suggestion.detected_purpose.matched_keyword,
            )
            if suggestion.detected_purpose is not None
            else None
        ),
    )


def _to_beneficiary_out(row: V2Beneficiary, repo: V2Repository) -> BeneficiaryOut:
    preg = (
        repo.get_active_pregnancy(row.id)
        if row.beneficiary_type == "pregnant_woman"
        else None
    )
    return BeneficiaryOut(
        id=row.local_code,
        label=row.full_name,
        uuid=row.id,
        local_code=row.local_code,
        full_name=row.full_name,
        beneficiary_type=row.beneficiary_type,
        sex=row.sex,
        dob=row.dob,
        dob_is_estimated=row.dob_is_estimated,
        area_id=row.area_id,
        area_name=repo.get_area_name(row.area_id),
        mother_id=row.mother_id,
        phone_masked=mask_phone(row.phone_enc),
        has_phone=bool(row.phone_enc and row.phone_enc.strip()),
        consent_id=row.consent_id,
        status=row.status,
        risk_level=row.risk_level,
        last_visit_at=row.last_visit_at,
        next_due_at=row.next_due_at,
        edd_date=preg.edd_date if preg is not None else None,
        version=row.version,
    )


@router.get("/beneficiaries", response_model=list[BeneficiaryOut])
def list_beneficiaries(
    asha_id: str = Query(...),
    beneficiary_type: str | None = Query(None),
    risk_level: str | None = Query(None),
    search: str | None = Query(None),
    repo: V2Repository = Depends(get_v2_repository),
) -> list[BeneficiaryOut]:
    """Return active beneficiaries for an ASHA worker with optional V2 filters."""
    rows = repo.list_beneficiaries(asha_id)
    if beneficiary_type:
        btype = beneficiary_type.strip().lower()
        rows = [r for r in rows if r.beneficiary_type.lower() == btype]
    if risk_level:
        rl = risk_level.strip().lower()
        rows = [r for r in rows if r.risk_level.lower() == rl]
    if search and search.strip():
        q = search.strip().lower()
        rows = [
            r
            for r in rows
            if q in r.full_name.lower()
            or q in r.local_code.lower()
            or (r.area_id and q in r.area_id.lower())
        ]
    return [_to_beneficiary_out(r, repo) for r in rows]


@router.post("/beneficiaries", response_model=BeneficiaryOut, status_code=201)
def create_beneficiary(
    payload: BeneficiaryCreateRequest,
    repo: V2Repository = Depends(get_v2_repository),
) -> BeneficiaryOut:
    """Create a new beneficiary after validating consent (SPEC_V2 §3.4)."""
    if not payload.consent_given:
        raise ApiError(
            "CONSENT_REQUIRED",
            "Beneficiary or guardian consent is required before saving.",
            400,
        )
    if not payload.full_name.strip():
        raise ApiError("INVALID_NAME", "Beneficiary name cannot be empty.", 400)

    resolved_lmp = payload.lmp_date
    if (
        payload.beneficiary_type == "pregnant_woman"
        and not resolved_lmp
        and payload.pregnancy_months is not None
        and 1 <= payload.pregnancy_months <= 10
    ):
        resolved_lmp = (
            date.today() - timedelta(days=payload.pregnancy_months * 30)
        ).isoformat()

    row = repo.create_beneficiary(
        beneficiary_id=payload.beneficiary_id,
        local_code=payload.local_code,
        worker_id=payload.worker_id,
        full_name=payload.full_name,
        beneficiary_type=payload.beneficiary_type,
        sex=payload.sex,
        dob=payload.dob,
        dob_is_estimated=payload.dob_is_estimated,
        area_id=payload.area_id,
        area_note=payload.area_note,
        household_id=payload.household_id,
        mother_id=payload.mother_id,
        phone_enc=payload.phone.strip() if payload.phone and payload.phone.strip() else None,
        external_id=payload.external_id,
        lmp_date=resolved_lmp,
        consent_given_by=payload.consent_given_by,
        consent_method=payload.consent_method,
    )
    return _to_beneficiary_out(row, repo)


@router.post("/beneficiaries/check-duplicate", response_model=list[DuplicateCandidateOut])
def check_duplicate_beneficiaries(
    payload: DuplicateCheckRequest,
    repo: V2Repository = Depends(get_v2_repository),
) -> list[DuplicateCandidateOut]:
    """Screen active beneficiaries in the same area for likely duplicates."""
    matches = repo.check_duplicates(
        worker_id=payload.worker_id,
        area_id=payload.area_id,
        full_name=payload.full_name,
        dob=payload.dob,
        phone_enc=payload.phone,
    )
    return [
        DuplicateCandidateOut(
            beneficiary_id=m.beneficiary_id,
            local_code=m.local_code,
            full_name=m.full_name,
            dob=m.dob,
            score=m.score,
            reasons=list(m.reasons),
        )
        for m in matches
    ]


@router.post("/beneficiaries/from-audio", response_model=BeneficiaryFromAudioResponse)
async def create_beneficiary_draft_from_audio(
    audio: UploadFile = File(...),
    language: str = Form("hi"),
    worker_id: str = Form("asha_001"),
    area_id: str | None = Form(None),
    settings: Settings = Depends(get_settings),
    http_client: httpx.AsyncClient | None = Depends(get_http_client),
    repo: V2Repository = Depends(get_v2_repository),
) -> BeneficiaryFromAudioResponse:
    """Transcribe spoken beneficiary details into an editable draft plus duplicate check."""
    _validate_language(language)
    audio_bytes = await audio.read()
    filename = audio.filename or "beneficiary.wav"
    stt = await stt_gnani.transcribe(
        audio_bytes,
        filename,
        language,
        settings=settings,
        client=http_client,
    )
    draft = extract_beneficiary_from_transcript(stt.transcript)
    dups = (
        repo.check_duplicates(
            worker_id=worker_id,
            area_id=area_id,
            full_name=draft.full_name,
            dob=draft.dob,
            phone_enc=draft.phone,
        )
        if draft.full_name.strip()
        else []
    )
    return BeneficiaryFromAudioResponse(
        transcript=stt.transcript,
        draft=BeneficiarySpeechDraftOut(
            full_name=draft.full_name,
            beneficiary_type=draft.beneficiary_type,
            sex=draft.sex,
            dob=draft.dob,
            dob_is_estimated=draft.dob_is_estimated,
            age_years=draft.age_years,
            age_days=draft.age_days,
            pregnancy_months=draft.pregnancy_months,
            lmp_date=draft.lmp_date,
            edd_date=draft.edd_date,
            area_note=draft.area_note,
            phone=draft.phone,
        ),
        duplicate_candidates=[
            DuplicateCandidateOut(
                beneficiary_id=m.beneficiary_id,
                local_code=m.local_code,
                full_name=m.full_name,
                dob=m.dob,
                score=m.score,
                reasons=list(m.reasons),
            )
            for m in dups
        ],
    )


@router.get("/beneficiaries/{beneficiary_id}", response_model=BeneficiaryOut)
def get_beneficiary_profile(
    beneficiary_id: str,
    worker_id: str | None = Query(None),
    repo: V2Repository = Depends(get_v2_repository),
) -> BeneficiaryOut:
    """Fetch a single beneficiary profile by UUID or local code."""
    row = repo.get_beneficiary_by_id_or_code(beneficiary_id, worker_id=worker_id)
    if row is None:
        raise ApiError("BENEFICIARY_NOT_FOUND", "Beneficiary not found.", 404)
    return _to_beneficiary_out(row, repo)


@router.patch("/beneficiaries/{beneficiary_id}", response_model=BeneficiaryOut)
def patch_beneficiary_profile(
    beneficiary_id: str,
    payload: BeneficiaryPatchRequest,
    worker_id: str = Query("asha_001"),
    repo: V2Repository = Depends(get_v2_repository),
) -> BeneficiaryOut:
    """Update editable profile metadata for a beneficiary."""
    target = repo.get_beneficiary_by_id_or_code(beneficiary_id, worker_id=worker_id)
    if target is None:
        raise ApiError("BENEFICIARY_NOT_FOUND", "Beneficiary not found.", 404)
    updates: dict[str, object] = {}
    for field_name in payload.model_fields_set:
        if field_name == "phone":
            val = getattr(payload, "phone")
            updates["phone_enc"] = val.strip() if isinstance(val, str) and val.strip() else None
        else:
            updates[field_name] = getattr(payload, field_name)
    updated = repo.update_beneficiary_fields(
        target.id,
        updates=updates,
        actor_id=worker_id,
    )
    if updated is None:
        raise ApiError("BENEFICIARY_NOT_FOUND", "Beneficiary not found.", 404)
    return _to_beneficiary_out(updated, repo)


@router.get(
    "/beneficiaries/{beneficiary_id}/visits",
    response_model=BeneficiaryVisitsResponse,
)
def list_beneficiary_visits(
    beneficiary_id: str,
    worker_id: str | None = Query(None),
    store: VisitStore = Depends(get_store),
    repo: V2Repository = Depends(get_v2_repository),
) -> BeneficiaryVisitsResponse:
    """Return visit timeline and normalized numeric measurements for a beneficiary."""
    ben = repo.get_beneficiary_by_id_or_code(beneficiary_id, worker_id=worker_id)
    codes = {beneficiary_id}
    if ben is not None:
        codes.add(ben.id)
        codes.add(ben.local_code)

    visits: list[VisitSummary] = []
    measurements: list[MeasurementPointOut] = []
    seen_ids: set[str] = set()

    if ben is not None:
        for v in repo.list_visits_for_beneficiary(ben.id):
            seen_ids.add(v.id)
            visits.append(
                VisitSummary(
                    visit_id=v.id,
                    session_id=v.id,
                    asha_id=v.worker_id,
                    beneficiary_id=ben.local_code,
                    visit_date=date.fromisoformat(v.visited_at[:10])
                    if v.visited_at
                    else None,
                    risk_flags=json.loads(v.risk_flags_json),
                    referral_suggested=v.referral_suggested,
                    status=v.status,
                    updated_at=v.updated_at,
                )
            )
        for m in repo.get_visit_measurements(ben.id):
            measurements.append(
                MeasurementPointOut(
                    key=m.key,
                    value_num=m.value_num,
                    unit=m.unit,
                    measured_at=m.measured_at,
                )
            )

    for s in store.list_visits(asha_id=worker_id, saved_only=True):
        sid_match = s.record.beneficiary_id and s.record.beneficiary_id.value in codes
        if not sid_match or (s.visit_id and s.visit_id in seen_ids) or s.session_id in seen_ids:
            continue
        visits.append(
            VisitSummary(
                visit_id=s.visit_id,
                session_id=s.session_id,
                asha_id=s.asha_id,
                beneficiary_id=s.record.beneficiary_id.value
                if s.record.beneficiary_id
                else None,
                visit_date=s.record.visit_date,
                risk_flags=s.record.risk_flags,
                referral_suggested=s.record.referral_suggested,
                status=s.status,
                updated_at=s.updated_at,
            )
        )
        measured_at = (
            s.record.visit_date.isoformat()
            if s.record.visit_date is not None
            else s.updated_at[:10]
        )
        payload = s.record.model_dump(mode="json")
        for key, value_num, unit in extract_numeric_measurements(payload):
            measurements.append(
                MeasurementPointOut(
                    key=key,
                    value_num=value_num,
                    unit=unit,
                    measured_at=measured_at,
                )
            )

    visits.sort(key=lambda v: v.updated_at, reverse=True)
    measurements.sort(key=lambda m: m.measured_at)
    return BeneficiaryVisitsResponse(
        beneficiary_id=ben.local_code if ben is not None else beneficiary_id,
        visits=visits,
        measurements=measurements,
    )


@router.post("/visits/audio", response_model=VisitTurnResponse)
async def upload_visit_audio(
    audio: UploadFile = File(...),
    language: str = Form(...),
    visit_type: str = Form("newborn_home_visit"),
    session_id: str | None = Form(None),
    beneficiary_id: str | None = Form(None),
    asha_id: str = Form("asha_001"),
    store: VisitStore = Depends(get_store),
    settings: Settings = Depends(get_settings),
    http_client: httpx.AsyncClient | None = Depends(get_http_client),
    repo: V2Repository = Depends(get_v2_repository),
) -> VisitTurnResponse:
    """Start or continue a visit by uploading spoken audio."""
    _validate_language(language)
    try:
        load_visit_config(visit_type)
    except ValueError as exc:
        raise ApiError("INVALID_VISIT_TYPE", str(exc), 400) from exc

    if session_id:
        session = _require_session(store, session_id)
        if session.status == "saved":
            raise ApiError("VISIT_ALREADY_CONFIRMED", "Visit is already confirmed.", 409)
    else:
        session = StoredSession(
            session_id=str(uuid.uuid4()),
            asha_id=asha_id,
            visit_type=visit_type,
            language=language,
        )

    if beneficiary_id and beneficiary_id.strip():
        session.record.beneficiary_id = ExtractedField(
            value=beneficiary_id.strip(),
            confidence=1.0,
            source=FieldSource.selected,
            needs_confirmation=False,
        )

    audio_bytes = await audio.read()
    filename = audio.filename or "recording.wav"
    return await _run_visit_turn(
        session,
        audio_bytes,
        filename,
        language,
        store=store,
        settings=settings,
        http_client=http_client,
        repo=repo,
    )


@router.post("/visits/{session_id}/answer", response_model=VisitTurnResponse)
async def answer_followup_audio(
    session_id: str,
    audio: UploadFile = File(...),
    language: str = Form(...),
    store: VisitStore = Depends(get_store),
    settings: Settings = Depends(get_settings),
    http_client: httpx.AsyncClient | None = Depends(get_http_client),
    repo: V2Repository = Depends(get_v2_repository),
) -> VisitTurnResponse:
    """Submit a spoken follow-up answer for an existing visit session."""
    _validate_language(language)
    session = _require_session(store, session_id)
    if session.status == "saved":
        raise ApiError("VISIT_ALREADY_CONFIRMED", "Visit is already confirmed.", 409)

    audio_bytes = await audio.read()
    filename = audio.filename or "answer.wav"
    return await _run_visit_turn(
        session,
        audio_bytes,
        filename,
        language,
        store=store,
        settings=settings,
        http_client=http_client,
        repo=repo,
    )


@router.patch("/visits/{session_id}/record", response_model=RecordPatchResponse)
def patch_visit_record(
    session_id: str,
    body: RecordPatchRequest,
    store: VisitStore = Depends(get_store),
    repo: V2Repository = Depends(get_v2_repository),
) -> RecordPatchResponse:
    """Apply typed/manual edits from the confirmation screen and re-validate."""
    session = _require_session(store, session_id)
    if session.status == "saved":
        raise ApiError("VISIT_ALREADY_CONFIRMED", "Visit is already confirmed.", 409)

    updated = session.record.model_copy(deep=True)
    for field_name in body.model_fields_set - {"source"}:
        val = getattr(body, field_name)
        if val is None:
            setattr(updated, field_name, None)
        else:
            setattr(
                updated,
                field_name,
                ExtractedField(
                    value=val,
                    confidence=1.0,
                    source=body.source,
                    needs_confirmation=False,
                ),
            )

    config = load_visit_config(session.visit_type)
    assigned_ids = get_assigned_ids(session.asha_id) | repo.list_local_codes_for_worker(
        session.asha_id
    )
    validation = validator.validate(
        updated,
        config,
        assigned_ids=assigned_ids,
    )
    final_record = risk_rules.apply_risk(validation.record, config)

    session.record = final_record
    session.flags = validation.flags
    session.ambiguities = filter_unresolved_ambiguities(final_record, session.ambiguities, set())
    if not validation.missing_required and session.status in ("draft", "error_retry"):
        session.status = "ready_to_confirm"
    elif not validation.missing_required and not session.ambiguities:
        session.status = "ready_to_confirm"
    store.create_or_update_session(session)

    return RecordPatchResponse(
        session_id=session.session_id,
        record=final_record,
        flags=validation.flags,
        risk_flags=final_record.risk_flags,
        referral_suggested=final_record.referral_suggested,
        status=session.status,
    )


@router.post("/visits/{session_id}/confirm", response_model=ConfirmResponse)
def confirm_visit(
    session_id: str,
    store: VisitStore = Depends(get_store),
) -> ConfirmResponse:
    """Finalize and persist a reviewed visit record."""
    session = _require_session(store, session_id)
    if session.status == "saved" and session.visit_id:
        return ConfirmResponse(visit_id=session.visit_id, status="saved")

    if session.record.visit_date is None:
        session.record.visit_date = date.today()
    session.visit_id = session.visit_id or str(uuid.uuid4())
    session.status = "saved"
    store.create_or_update_session(session)
    return ConfirmResponse(visit_id=session.visit_id, status="saved")


@router.get("/visits", response_model=list[VisitSummary])
def list_visits(
    asha_id: str | None = Query(None),
    include_drafts: bool = Query(False),
    flagged_only: bool = Query(False),
    store: VisitStore = Depends(get_store),
) -> list[VisitSummary]:
    """List saved visits (and optionally drafts or flagged cases) for ASHA/supervisor view."""
    sessions = store.list_visits(asha_id=asha_id, saved_only=not include_drafts)
    if flagged_only:
        sessions = [
            s for s in sessions if s.record.referral_suggested or bool(s.record.risk_flags)
        ]
    return [
        VisitSummary(
            visit_id=s.visit_id,
            session_id=s.session_id,
            asha_id=s.asha_id,
            beneficiary_id=s.record.beneficiary_id.value if s.record.beneficiary_id else None,
            visit_date=s.record.visit_date,
            risk_flags=s.record.risk_flags,
            referral_suggested=s.record.referral_suggested,
            status=s.status,
            updated_at=s.updated_at,
        )
        for s in sessions
    ]


@router.get("/visits/{session_id}", response_model=StoredSession)
def get_visit_detail(
    session_id: str,
    store: VisitStore = Depends(get_store),
) -> StoredSession:
    """Return full stored state for a visit session."""
    return _require_session(store, session_id)


@router.get("/visits/{session_id}/readback", response_model=ReadbackResponse)
async def get_visit_readback(
    session_id: str,
    language: str = Query("hi"),
    store: VisitStore = Depends(get_store),
    settings: Settings = Depends(get_settings),
    http_client: httpx.AsyncClient | None = Depends(get_http_client),
) -> ReadbackResponse:
    """Generate spoken read-back confirmation text and audio for ID, weight, and temperature."""
    _validate_language(language)
    session = _require_session(store, session_id)
    text = build_readback_text(session.record, language)
    audio_url = await _try_tts_url(
        text,
        language,
        store=store,
        settings=settings,
        client=http_client,
    )
    return ReadbackResponse(text=text, audio_url=audio_url)


@router.get("/audio/{audio_id}")
def get_audio_clip(
    audio_id: str,
    store: VisitStore = Depends(get_store),
) -> Response:
    """Serve stored TTS MP3 audio bytes by audio_id."""
    item = store.get_audio(audio_id)
    if item is None:
        raise ApiError("AUDIO_NOT_FOUND", "Audio clip not found.", 404)
    data, content_type = item
    return Response(content=data, media_type=content_type)


@router.post("/sync", response_model=SyncResponse)
async def sync_offline_queue(
    items: list[SyncItemRequest],
    store: VisitStore = Depends(get_store),
    settings: Settings = Depends(get_settings),
    http_client: httpx.AsyncClient | None = Depends(get_http_client),
    repo: V2Repository = Depends(get_v2_repository),
) -> SyncResponse:
    """Process a batch of offline queued audio recordings idempotently by client_id."""
    results: list[SyncItemResult] = []
    for item in items:
        cached = store.get_sync_result(item.client_id)
        if cached is not None:
            results.append(SyncItemResult.model_validate(cached))
            continue

        try:
            _validate_language(item.language)
            load_visit_config(item.visit_type)
            try:
                audio_bytes = base64.b64decode(item.audio_base64, validate=True)
            except (binascii.Error, ValueError) as exc:
                raise ApiError("INVALID_AUDIO", "Invalid base64 audio payload.", 400) from exc

            session = StoredSession(
                session_id=str(uuid.uuid4()),
                asha_id=item.asha_id,
                visit_type=item.visit_type,
                language=item.language,
            )
            if item.beneficiary_id and item.beneficiary_id.strip():
                session.record.beneficiary_id = ExtractedField(
                    value=item.beneficiary_id.strip(),
                    confidence=1.0,
                    source=FieldSource.selected,
                    needs_confirmation=False,
                )

            turn_res = await _run_visit_turn(
                session,
                audio_bytes,
                item.filename,
                item.language,
                store=store,
                settings=settings,
                http_client=http_client,
                repo=repo,
            )
            item_result = SyncItemResult(client_id=item.client_id, ok=True, result=turn_res)
            store.save_sync_result(item.client_id, item_result.model_dump(mode="json"))
        except ValueError as exc:
            item_result = SyncItemResult(
                client_id=item.client_id,
                ok=False,
                error={"code": "INVALID_VISIT_TYPE", "message": str(exc)},
            )
        except ApiError as exc:
            item_result = SyncItemResult(
                client_id=item.client_id,
                ok=False,
                error={"code": exc.code, "message": exc.message},
            )
        results.append(item_result)

    return SyncResponse(results=results)


@router.post("/auth/login", response_model=LoginResponse)
def auth_login(payload: LoginRequest) -> LoginResponse:
    """Authenticate an ASHA worker via synthetic worker code and PIN (SPEC_V2 §3.1, §9)."""
    worker = verify_worker_credentials(payload.worker_code, payload.pin)
    if worker is None:
        raise ApiError("INVALID_CREDENTIALS", "Invalid worker code or PIN.", 401)
    return LoginResponse(
        token=secrets.token_urlsafe(32),
        worker=WorkerProfile(**worker),
    )
