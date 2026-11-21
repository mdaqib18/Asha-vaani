"""Gnani Prisma Speech-to-Text REST client."""

from __future__ import annotations

import json
import uuid
from pathlib import Path

import httpx
from pydantic import BaseModel

from app.core.errors import ApiError
from app.core.settings import Settings, get_settings
from app.services.gnani_common import (
    LANGUAGE_MAP,
    STT_LANGUAGE_HINTS,
    execute_with_retry,
    parse_gnani_error,
)

ALLOWED_AUDIO_EXTENSIONS: set[str] = {"wav", "mp3", "ogg", "flac", "aac", "m4a"}

_AUDIO_MIME_TYPES: dict[str, str] = {
    "wav": "audio/wav",
    "mp3": "audio/mpeg",
    "ogg": "audio/ogg",
    "flac": "audio/flac",
    "aac": "audio/aac",
    "m4a": "audio/mp4",
}

_AUDIO_ERROR_TYPES: set[str] = {
    "EMPTY_AUDIO",
    "UNSUPPORTED_AUDIO_FORMAT",
    "AUDIO_CONVERSION_ERROR",
    "MAX_AUDIO_DURATION_EXCEEDED",
}

NEWBORN_KEYTERMS: list[str] = [
    "weight",
    "kg",
    "kilo",
    "gram",
    "temperature",
    "degree",
    "fahrenheit",
    "breastfeeding",
    "cord",
    "jaundice",
    "breathing",
    "beneficiary",
    "limb",
    "ASHA",
    "ANM",
    "वजन",
    "बुखार",
    "पीलिया",
    "स्तनपान",
    "नाल",
    "ತೂಕ",
    "ಜ್ವರ",
    "ಕಾಮಾಲೆ",
]

NEWBORN_TOPIC: str = (
    "Newborn home visit record by an ASHA health worker: beneficiary ID, "
    "baby weight, temperature, breastfeeding, umbilical cord, jaundice, "
    "breathing, limb problems."
)


class SttResult(BaseModel):
    """Normalized transcription metadata returned by Gnani Prisma."""

    transcript: str
    detected_language: str | None = None
    model: str | None = None
    request_id: str | None = None
    latency_s: float | None = None
    truncated: bool = False


async def transcribe(
    audio: bytes,
    filename: str,
    language: str,
    *,
    settings: Settings | None = None,
    client: httpx.AsyncClient | None = None,
    retry_delay_s: float = 1.0,
) -> SttResult:
    """Transcribe an audio clip (<= 30s) via Gnani Prisma REST API."""
    cfg = settings or get_settings()
    if not cfg.GNANI_API_KEY or not cfg.GNANI_API_KEY.strip():
        raise ApiError(
            "STT_NOT_CONFIGURED",
            "Speech-to-text service is not configured.",
            503,
        )

    if language not in LANGUAGE_MAP:
        raise ApiError(
            "INVALID_LANGUAGE",
            f"Unsupported language code: {language}",
            400,
        )

    ext = Path(filename).suffix.lstrip(".").lower()
    if not audio or ext not in ALLOWED_AUDIO_EXTENSIONS:
        raise ApiError(
            "INVALID_AUDIO",
            "Audio is empty or has an unsupported format.",
            400,
        )

    is_v3 = cfg.GNANI_STT_MODEL == "prisma-v3.0"
    form_data: dict[str, str] = {
        "model": cfg.GNANI_STT_MODEL,
        "language_code": STT_LANGUAGE_HINTS[language] if is_v3 else LANGUAGE_MAP[language],
        "format": cfg.GNANI_STT_FORMAT,
    }
    if is_v3:
        form_data["keyterms"] = json.dumps(NEWBORN_KEYTERMS, ensure_ascii=False)
        form_data["topic"] = NEWBORN_TOPIC

    mime = _AUDIO_MIME_TYPES[ext]
    headers = {
        "X-API-Key-ID": cfg.GNANI_API_KEY,
        "X-API-Request-ID": str(uuid.uuid4()),
    }

    resp = await execute_with_retry(
        lambda c: c.post(
            cfg.GNANI_STT_URL,
            headers=headers,
            data=form_data,
            files={"audio_file": (filename, audio, mime)},
        ),
        timeout_s=cfg.GNANI_TIMEOUT_S,
        retry_delay_s=retry_delay_s,
        error_prefix="STT",
        client=client,
    )

    if resp.status_code != 200:
        gnani_type, gnani_msg = parse_gnani_error(resp)
        if resp.status_code == 400 and gnani_type in _AUDIO_ERROR_TYPES:
            raise ApiError(
                "INVALID_AUDIO",
                f"Invalid audio ({gnani_type}): {gnani_msg}",
                400,
            )
        if resp.status_code in (401, 402, 403):
            raise ApiError(
                "STT_AUTH_FAILED",
                f"Speech recognition authorization failed ({gnani_type}).",
                502,
            )
        if resp.status_code == 429:
            raise ApiError(
                "STT_RATE_LIMITED",
                f"Speech recognition is temporarily busy ({gnani_type}). Please retry.",
                503,
            )
        raise ApiError(
            "STT_FAILED",
            f"Speech recognition failed ({gnani_type}). Please try again.",
            502,
        )

    try:
        payload = resp.json()
    except Exception as exc:
        raise ApiError(
            "STT_FAILED",
            "Speech recognition returned an invalid response.",
            502,
        ) from exc

    if not isinstance(payload, dict) or not isinstance(payload.get("transcript"), str):
        raise ApiError(
            "STT_FAILED",
            "Speech recognition response missed transcript text.",
            502,
        )

    return SttResult(
        transcript=payload["transcript"],
        detected_language=payload.get("detected_language_code"),
        model=payload.get("model"),
        request_id=payload.get("request_id"),
        latency_s=payload.get("end_to_end_latency"),
        truncated=bool(payload.get("truncated", False)),
    )
