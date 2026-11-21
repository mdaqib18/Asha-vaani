import asyncio
import json
import re

import httpx
import pytest

from app.core.errors import ApiError
from app.core.settings import Settings
from app.services.stt_gnani import NEWBORN_KEYTERMS, NEWBORN_TOPIC, transcribe


def _settings(**overrides) -> Settings:
    return Settings(GNANI_API_KEY="test-key", **overrides)


def _parse_multipart(request: httpx.Request) -> dict[str, tuple[str | None, str]]:
    """Parse form field values and filenames from an httpx multipart request."""
    content_type = request.headers["content-type"]
    match = re.search(r"boundary=([^\s;]+)", content_type)
    assert match is not None
    boundary = match.group(1).strip('"')
    raw = request.content.decode("utf-8", errors="replace")
    parts = raw.split(f"--{boundary}")
    parsed: dict[str, tuple[str | None, str]] = {}
    for part in parts:
        if "Content-Disposition:" not in part:
            continue
        head, _, body = part.partition("\r\n\r\n")
        body = body.removesuffix("\r\n")
        name_m = re.search(r'name="([^"]+)"', head)
        file_m = re.search(r'filename="([^"]+)"', head)
        if name_m:
            parsed[name_m.group(1)] = (file_m.group(1) if file_m else None, body)
    return parsed


def test_transcribe_success_and_request_inspection() -> None:
    captured: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        captured.append(request)
        return httpx.Response(
            200,
            json={
                "success": True,
                "request_id": "req-123",
                "transcript": "weight 2.5 kg",
                "model": "prisma-v3.0",
                "detected_language_code": "hi-IN",
                "processing_time": 0.41,
                "end_to_end_latency": 0.55,
            },
        )

    transport = httpx.MockTransport(handler)

    async def _run():
        async with httpx.AsyncClient(transport=transport) as client:
            return await transcribe(
                b"RIFFfakewav",
                "visit.wav",
                "hi",
                settings=_settings(),
                client=client,
                retry_delay_s=0,
            )

    result = asyncio.run(_run())
    assert result.transcript == "weight 2.5 kg"
    assert result.detected_language == "hi-IN"
    assert result.model == "prisma-v3.0"
    assert result.request_id == "req-123"
    assert result.latency_s == 0.55
    assert result.truncated is False

    assert len(captured) == 1
    req = captured[0]
    assert str(req.url) == "https://api.vachana.ai/stt/v3"
    assert req.headers["x-api-key-id"] == "test-key"
    assert "x-api-request-id" in req.headers
    fields = _parse_multipart(req)
    assert fields["audio_file"][0] == "visit.wav"
    assert fields["audio_file"][1] == "RIFFfakewav"
    assert fields["model"][1] == "prisma-v3.0"
    assert fields["language_code"][1] == "hi-IN,en-IN"
    assert fields["format"][1] == "transcribe"
    assert json.loads(fields["keyterms"][1]) == NEWBORN_KEYTERMS
    assert fields["topic"][1] == NEWBORN_TOPIC


def test_transcribe_kannada_language_hints() -> None:
    captured_fields: dict[str, tuple[str | None, str]] = {}

    def handler(request: httpx.Request) -> httpx.Response:
        captured_fields.update(_parse_multipart(request))
        return httpx.Response(200, json={"success": True, "transcript": "2.5 kg"})

    async def _run():
        async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
            return await transcribe(
                b"audio",
                "clip.mp3",
                "kn",
                settings=_settings(),
                client=client,
                retry_delay_s=0,
            )

    result = asyncio.run(_run())
    assert result.transcript == "2.5 kg"
    assert captured_fields["language_code"][1] == "kn-IN,en-IN"


def test_transcribe_empty_transcript_allowed() -> None:
    def handler(_request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, json={"success": True, "request_id": "r1", "transcript": ""})

    async def _run():
        async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
            return await transcribe(
                b"audio",
                "short.wav",
                "en",
                settings=_settings(),
                client=client,
                retry_delay_s=0,
            )

    result = asyncio.run(_run())
    assert result.transcript == ""


def test_transcribe_400_empty_audio_maps_to_invalid_audio() -> None:
    def handler(_request: httpx.Request) -> httpx.Response:
        return httpx.Response(
            400,
            json={"success": False, "error": {"type": "EMPTY_AUDIO", "message": "Empty audio file"}},
        )

    async def _run():
        async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
            await transcribe(
                b"audio",
                "bad.wav",
                "hi",
                settings=_settings(),
                client=client,
                retry_delay_s=0,
            )

    with pytest.raises(ApiError) as exc_info:
        asyncio.run(_run())
    assert exc_info.value.code == "INVALID_AUDIO"
    assert exc_info.value.http_status == 400


def test_transcribe_401_maps_to_auth_failed() -> None:
    def handler(_request: httpx.Request) -> httpx.Response:
        return httpx.Response(
            401,
            json={"detail": {"error_code": "INVALID_API_KEY", "message": "Unauthorized", "status_code": 401}},
        )

    async def _run():
        async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
            await transcribe(
                b"audio",
                "visit.wav",
                "hi",
                settings=_settings(),
                client=client,
                retry_delay_s=0,
            )

    with pytest.raises(ApiError) as exc_info:
        asyncio.run(_run())
    assert exc_info.value.code == "STT_AUTH_FAILED"
    assert exc_info.value.http_status == 502
    assert "test-key" not in exc_info.value.message


def test_transcribe_retries_once_on_429_then_succeeds() -> None:
    calls = 0

    def handler(_request: httpx.Request) -> httpx.Response:
        nonlocal calls
        calls += 1
        if calls == 1:
            return httpx.Response(
                429,
                json={"detail": {"error_code": "RATE_LIMITED", "message": "Busy", "status_code": 429}},
            )
        return httpx.Response(200, json={"success": True, "transcript": "ok"})

    async def _run():
        async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
            return await transcribe(
                b"audio",
                "visit.wav",
                "hi",
                settings=_settings(),
                client=client,
                retry_delay_s=0,
            )

    result = asyncio.run(_run())
    assert calls == 2
    assert result.transcript == "ok"


def test_transcribe_500_twice_fails_after_retry() -> None:
    calls = 0

    def handler(_request: httpx.Request) -> httpx.Response:
        nonlocal calls
        calls += 1
        return httpx.Response(
            500,
            json={"success": False, "error": {"type": "TRANSCRIPTION_FAILED", "message": "Failed"}},
        )

    async def _run():
        async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
            await transcribe(
                b"audio",
                "visit.wav",
                "hi",
                settings=_settings(),
                client=client,
                retry_delay_s=0,
            )

    with pytest.raises(ApiError) as exc_info:
        asyncio.run(_run())
    assert calls == 2
    assert exc_info.value.code == "STT_FAILED"
    assert exc_info.value.http_status == 502


def test_transcribe_504_twice_fails_after_retry() -> None:
    calls = 0

    def handler(_request: httpx.Request) -> httpx.Response:
        nonlocal calls
        calls += 1
        return httpx.Response(
            504,
            json={"error": "Gateway Timeout", "code": "UPSTREAM_TIMEOUT", "message": "Timed out"},
        )

    async def _run():
        async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
            await transcribe(
                b"audio",
                "visit.wav",
                "hi",
                settings=_settings(),
                client=client,
                retry_delay_s=0,
            )

    with pytest.raises(ApiError) as exc_info:
        asyncio.run(_run())
    assert calls == 2
    assert exc_info.value.code == "STT_FAILED"
    assert "UPSTREAM_TIMEOUT" in exc_info.value.message


def test_transcribe_missing_key_skips_http() -> None:
    calls = 0

    def handler(_request: httpx.Request) -> httpx.Response:
        nonlocal calls
        calls += 1
        return httpx.Response(200)

    async def _run():
        async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
            await transcribe(
                b"audio",
                "visit.wav",
                "hi",
                settings=Settings(GNANI_API_KEY=""),
                client=client,
                retry_delay_s=0,
            )

    with pytest.raises(ApiError) as exc_info:
        asyncio.run(_run())
    assert calls == 0
    assert exc_info.value.code == "STT_NOT_CONFIGURED"
    assert exc_info.value.http_status == 503


def test_transcribe_invalid_extension_skips_http() -> None:
    calls = 0

    def handler(_request: httpx.Request) -> httpx.Response:
        nonlocal calls
        calls += 1
        return httpx.Response(200)

    async def _run():
        async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
            await transcribe(
                b"audio",
                "notes.txt",
                "hi",
                settings=_settings(),
                client=client,
                retry_delay_s=0,
            )

    with pytest.raises(ApiError) as exc_info:
        asyncio.run(_run())
    assert calls == 0
    assert exc_info.value.code == "INVALID_AUDIO"
    assert exc_info.value.http_status == 400


def test_transcribe_unknown_language() -> None:
    with pytest.raises(ApiError) as exc_info:
        asyncio.run(
            transcribe(
                b"audio",
                "visit.wav",
                "fr",
                settings=_settings(),
                retry_delay_s=0,
            )
        )
    assert exc_info.value.code == "INVALID_LANGUAGE"
    assert exc_info.value.http_status == 400
