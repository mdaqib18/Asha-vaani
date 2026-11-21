import asyncio
import json

import httpx
import pytest

from app.core.errors import ApiError
from app.core.settings import Settings
from app.services.llm_client import generate_json


def _settings(**overrides) -> Settings:
    defaults = {
        "LLM_PROVIDER": "gemini",
        "LLM_API_KEY": "test-gemini-key",
        "LLM_MODEL": "gemini-2.5-flash",
    }
    defaults.update(overrides)
    return Settings(**defaults)


def _gemini_ok(parts: list[dict]) -> httpx.Response:
    return httpx.Response(
        200,
        json={"candidates": [{"content": {"role": "model", "parts": parts}}]},
    )


def test_generate_json_gemini_request_and_response() -> None:
    captured: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        captured.append(request)
        return _gemini_ok([{"text": '{"ok": true}'}])

    async def _run():
        async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
            return await generate_json(
                "sys prompt",
                "user prompt",
                settings=_settings(),
                client=client,
                retry_delay_s=0,
            )

    res = asyncio.run(_run())
    assert res.text == '{"ok": true}'
    assert res.model == "gemini-2.5-flash"
    assert res.latency_s >= 0.0

    assert len(captured) == 1
    req = captured[0]
    assert (
        str(req.url)
        == "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent"
    )
    assert "test-gemini-key" not in str(req.url)
    assert req.headers["x-goog-api-key"] == "test-gemini-key"

    body = json.loads(req.content.decode("utf-8"))
    assert body["systemInstruction"] == {"parts": [{"text": "sys prompt"}]}
    assert body["contents"] == [{"role": "user", "parts": [{"text": "user prompt"}]}]
    assert body["generationConfig"]["responseMimeType"] == "application/json"
    assert body["generationConfig"]["temperature"] == 0.0


def test_generate_json_skips_thinking_parts() -> None:
    def handler(_request: httpx.Request) -> httpx.Response:
        return _gemini_ok(
            [
                {"thought": True, "text": "internal reasoning"},
                {"text": '{"beneficiary_id": {"value": "1042"}}'},
            ]
        )

    async def _run():
        async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
            return await generate_json(
                "sys",
                "usr",
                settings=_settings(),
                client=client,
                retry_delay_s=0,
            )

    res = asyncio.run(_run())
    assert res.text == '{"beneficiary_id": {"value": "1042"}}'


def test_generate_json_401_maps_to_auth_failed() -> None:
    def handler(_request: httpx.Request) -> httpx.Response:
        return httpx.Response(
            401,
            json={"error": {"code": 401, "message": "API key invalid", "status": "UNAUTHENTICATED"}},
        )

    async def _run():
        async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
            await generate_json(
                "sys",
                "usr",
                settings=_settings(),
                client=client,
                retry_delay_s=0,
            )

    with pytest.raises(ApiError) as exc_info:
        asyncio.run(_run())
    assert exc_info.value.code == "LLM_AUTH_FAILED"
    assert exc_info.value.http_status == 502
    assert "test-gemini-key" not in exc_info.value.message


def test_generate_json_429_retries_once_then_succeeds() -> None:
    calls = 0

    def handler(_request: httpx.Request) -> httpx.Response:
        nonlocal calls
        calls += 1
        if calls == 1:
            return httpx.Response(
                429,
                json={"error": {"code": 429, "message": "Quota exceeded", "status": "RESOURCE_EXHAUSTED"}},
            )
        return _gemini_ok([{"text": "{}"}])

    async def _run():
        async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
            return await generate_json(
                "sys",
                "usr",
                settings=_settings(),
                client=client,
                retry_delay_s=0,
            )

    res = asyncio.run(_run())
    assert calls == 2
    assert res.text == "{}"


def test_generate_json_500_twice_fails_after_retry() -> None:
    calls = 0

    def handler(_request: httpx.Request) -> httpx.Response:
        nonlocal calls
        calls += 1
        return httpx.Response(
            500,
            json={"error": {"code": 500, "message": "Internal error", "status": "INTERNAL"}},
        )

    async def _run():
        async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
            await generate_json(
                "sys",
                "usr",
                settings=_settings(),
                client=client,
                retry_delay_s=0,
            )

    with pytest.raises(ApiError) as exc_info:
        asyncio.run(_run())
    assert calls == 2
    assert exc_info.value.code == "LLM_FAILED"
    assert exc_info.value.http_status == 502


def test_generate_json_missing_key_skips_http() -> None:
    calls = 0

    def handler(_request: httpx.Request) -> httpx.Response:
        nonlocal calls
        calls += 1
        return _gemini_ok([{"text": "{}"}])

    async def _run():
        async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
            await generate_json(
                "sys",
                "usr",
                settings=_settings(LLM_API_KEY=""),
                client=client,
                retry_delay_s=0,
            )

    with pytest.raises(ApiError) as exc_info:
        asyncio.run(_run())
    assert calls == 0
    assert exc_info.value.code == "LLM_NOT_CONFIGURED"
    assert exc_info.value.http_status == 503


def test_generate_json_unsupported_provider_skips_http() -> None:
    calls = 0

    def handler(_request: httpx.Request) -> httpx.Response:
        nonlocal calls
        calls += 1
        return _gemini_ok([{"text": "{}"}])

    async def _run():
        async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
            await generate_json(
                "sys",
                "usr",
                settings=_settings(LLM_PROVIDER="openai"),
                client=client,
                retry_delay_s=0,
            )

    with pytest.raises(ApiError) as exc_info:
        asyncio.run(_run())
    assert calls == 0
    assert exc_info.value.code == "LLM_UNSUPPORTED_PROVIDER"
    assert exc_info.value.http_status == 503
