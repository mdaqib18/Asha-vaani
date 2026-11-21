"""Gnani Timbre Text-to-Speech REST client."""

from __future__ import annotations

import uuid

import httpx

from app.core.errors import ApiError
from app.core.settings import Settings, get_settings
from app.services.gnani_common import LANGUAGE_MAP, execute_with_retry, parse_gnani_error

TTS_CONTENT_TYPE: str = "audio/mpeg"


async def synthesize(
    text: str,
    language: str,
    *,
    settings: Settings | None = None,
    client: httpx.AsyncClient | None = None,
    retry_delay_s: float = 1.0,
) -> bytes:
    """Synthesize speech audio bytes (MP3) via Gnani Timbre REST API."""
    cfg = settings or get_settings()
    if not cfg.GNANI_API_KEY or not cfg.GNANI_API_KEY.strip():
        raise ApiError(
            "TTS_NOT_CONFIGURED",
            "Text-to-speech service is not configured.",
            503,
        )

    if language not in LANGUAGE_MAP:
        raise ApiError(
            "INVALID_LANGUAGE",
            f"Unsupported language code: {language}",
            400,
        )

    if not text or not text.strip():
        raise ApiError(
            "INVALID_TEXT",
            "Text to synthesize must not be empty.",
            400,
        )

    headers = {
        "Content-Type": "application/json",
        "X-API-Key-ID": cfg.GNANI_API_KEY,
        "X-API-Request-ID": str(uuid.uuid4()),
    }
    body = {
        "text": text,
        "voice": cfg.GNANI_TTS_VOICE,
        "model": cfg.GNANI_TTS_MODEL,
        "language": LANGUAGE_MAP[language],
        "speed": 1.0,
        "audio_config": {
            "sample_rate": 24000,
            "num_channels": 1,
            "sample_width": 2,
            "container": "mp3",
            "bitrate": "64k",
        },
    }

    resp = await execute_with_retry(
        lambda c: c.post(cfg.GNANI_TTS_URL, headers=headers, json=body),
        timeout_s=cfg.GNANI_TIMEOUT_S,
        retry_delay_s=retry_delay_s,
        error_prefix="TTS",
        client=client,
    )

    if resp.status_code != 200:
        gnani_type, _gnani_msg = parse_gnani_error(resp)
        if resp.status_code in (401, 402, 403):
            raise ApiError(
                "TTS_AUTH_FAILED",
                f"Text-to-speech authorization failed ({gnani_type}).",
                502,
            )
        if resp.status_code == 429:
            raise ApiError(
                "TTS_RATE_LIMITED",
                f"Text-to-speech is temporarily busy ({gnani_type}). Please retry.",
                503,
            )
        raise ApiError(
            "TTS_FAILED",
            f"Text-to-speech synthesis failed ({gnani_type}). Please try again.",
            502,
        )

    if not resp.content:
        raise ApiError(
            "TTS_FAILED",
            "Text-to-speech returned empty audio.",
            502,
        )

    return resp.content
