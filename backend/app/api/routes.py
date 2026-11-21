from __future__ import annotations

import base64
import binascii
import uuid
from datetime import date

import httpx
from fastapi import APIRouter, Depends, File, Form, Query, Response, UploadFile

from app.core.config_loader import load_visit_config
from app.core.errors import ApiError
from app.core.settings import Settings, get_settings
from app.data.beneficiaries import get_assigned_ids, get_beneficiaries
from app.db.store import StoredSession, VisitStore, get_store
from app.schemas.api import (
    ConfirmResponse,
    ReadbackResponse,
    RecordPatchRequest,
    RecordPatchResponse,
    SyncItemRequest,
    SyncItemResult,
    SyncResponse,
    VisitSummary,
    VisitTurnResponse,
)
from app.schemas.newborn_visit import ExtractedField, FieldSource
from app.services import risk_rules, tts_gnani, validator
from app.services.followup import (
    FollowupPayload,
    build_readback_text,
    decide_followup,
    filter_unresolved_ambiguities,
)
from app.services.gnani_common import LANGUAGE_MAP
from app.services.pipeline import process_audio
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
) -> VisitTurnResponse:
    prev_snapshot = session.record.model_dump(mode="json")
    assigned_ids = get_assigned_ids(session.asha_id)

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
    )


@router.get("/health")
def health() -> dict[str, str]:
    """Liveness check."""
    return {"status": "ok"}


@router.get("/beneficiaries")
def list_beneficiaries(asha_id: str = Query(...)) -> list[dict[str, str]]:
    """Return assigned synthetic beneficiaries for an ASHA worker."""
    return get_beneficiaries(asha_id)


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
    )


@router.post("/visits/{session_id}/answer", response_model=VisitTurnResponse)
async def answer_followup_audio(
    session_id: str,
    audio: UploadFile = File(...),
    language: str = Form(...),
    store: VisitStore = Depends(get_store),
    settings: Settings = Depends(get_settings),
    http_client: httpx.AsyncClient | None = Depends(get_http_client),
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
    )


@router.patch("/visits/{session_id}/record", response_model=RecordPatchResponse)
def patch_visit_record(
    session_id: str,
    body: RecordPatchRequest,
    store: VisitStore = Depends(get_store),
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
    validation = validator.validate(
        updated,
        config,
        assigned_ids=get_assigned_ids(session.asha_id),
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
    store: VisitStore = Depends(get_store),
) -> list[VisitSummary]:
    """List saved visits (and optionally drafts) for an ASHA worker."""
    sessions = store.list_visits(asha_id=asha_id, saved_only=not include_drafts)
    return [
        VisitSummary(
            visit_id=s.visit_id,
            session_id=s.session_id,
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
