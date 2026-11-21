import asyncio
import json

import httpx
import pytest

from app.core.errors import ApiError
from app.core.settings import Settings
from app.services.tts_gnani import synthesize


def _settings(**overrides) -> Settings:
    return Settings(GNANI_API_KEY="test-key", **overrides)


def test_synthesize_success_and_request_body() -> None:
    captured: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        captured.append(request)
        return httpx.Response(200, content=b"ID3fakemp3bytes", headers={"content-type": "audio/mpeg"})

    async def _run():
        async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
            return await synthesize(
                "ಮಗುವಿನ ತೂಕ ಎಷ್ಟು?",
                "kn",
                settings=_settings(),
                client=client,
                retry_delay_s=0,
            )

    audio = asyncio.run(_run())
    assert audio == b"ID3fakemp3bytes"
    assert len(captured) == 1
    req = captured[0]
    assert str(req.url) == "https://api.vachana.ai/api/v1/tts/inference"
    assert req.headers["x-api-key-id"] == "test-key"
    body = json.loads(req.content.decode("utf-8"))
    assert body["model"] == "timbre-v3.0"
    assert body["voice"] == "Lakshmi"
    assert body["language"] == "kn-IN"
    assert body["speed"] == 1.0
    assert body["audio_config"] == {
        "sample_rate": 24000,
        "num_channels": 1,
        "sample_width": 2,
        "container": "mp3",
        "bitrate": "64k",
    }


def test_synthesize_flat_400_maps_to_tts_failed() -> None:
    def handler(_request: httpx.Request) -> httpx.Response:
        return httpx.Response(
            400,
            json={"success": False, "message": "Unknown voice", "status_code": 400},
        )

    async def _run():
        async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
            await synthesize(
                "hello",
                "en",
                settings=_settings(),
                client=client,
                retry_delay_s=0,
            )

    with pytest.raises(ApiError) as exc_info:
        asyncio.run(_run())
    assert exc_info.value.code == "TTS_FAILED"
    assert exc_info.value.http_status == 502


def test_synthesize_401_maps_to_auth_failed() -> None:
    def handler(_request: httpx.Request) -> httpx.Response:
        return httpx.Response(
            401,
            json={"detail": {"error_code": "INVALID_API_KEY", "message": "Unauthorized", "status_code": 401}},
        )

    async def _run():
        async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
            await synthesize(
                "hello",
                "hi",
                settings=_settings(),
                client=client,
                retry_delay_s=0,
            )

    with pytest.raises(ApiError) as exc_info:
        asyncio.run(_run())
    assert exc_info.value.code == "TTS_AUTH_FAILED"
    assert exc_info.value.http_status == 502


def test_synthesize_missing_key_skips_http() -> None:
    calls = 0

    def handler(_request: httpx.Request) -> httpx.Response:
        nonlocal calls
        calls += 1
        return httpx.Response(200, content=b"bytes")

    async def _run():
        async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
            await synthesize(
                "hello",
                "hi",
                settings=Settings(GNANI_API_KEY=None),
                client=client,
                retry_delay_s=0,
            )

    with pytest.raises(ApiError) as exc_info:
        asyncio.run(_run())
    assert calls == 0
    assert exc_info.value.code == "TTS_NOT_CONFIGURED"
    assert exc_info.value.http_status == 503


def test_synthesize_empty_text() -> None:
    with pytest.raises(ApiError) as exc_info:
        asyncio.run(synthesize("   ", "hi", settings=_settings(), retry_delay_s=0))
    assert exc_info.value.code == "INVALID_TEXT"
    assert exc_info.value.http_status == 400
