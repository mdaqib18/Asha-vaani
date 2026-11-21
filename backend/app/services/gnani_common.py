"""Shared language mappings, error parsing, and retry helpers for Gnani Speech APIs."""

from __future__ import annotations

import asyncio
from collections.abc import Awaitable, Callable

import httpx

from app.core.errors import ApiError

LANGUAGE_MAP: dict[str, str] = {
    "hi": "hi-IN",
    "kn": "kn-IN",
    "en": "en-IN",
}

STT_LANGUAGE_HINTS: dict[str, str] = {
    "hi": "hi-IN,en-IN",
    "kn": "kn-IN,en-IN",
    "en": "en-IN",
}

_RETRYABLE_STATUSES = {429, 500, 502, 503, 504}


def parse_gnani_error(resp: httpx.Response) -> tuple[str, str]:
    """Extract (gnani_type, message) across all Gnani REST error shapes without raising."""
    fallback_code = f"HTTP_{resp.status_code}"
    try:
        data = resp.json()
    except Exception:
        text = (resp.text or "").strip()
        return fallback_code, text[:300] if text else f"HTTP {resp.status_code}"

    if not isinstance(data, dict):
        return fallback_code, str(data)[:300]

    # (a) STT envelope: {"success": false, "error": {"type": "...", "message": "..."}}
    err = data.get("error")
    if isinstance(err, dict):
        code = str(err.get("type") or err.get("code") or fallback_code)
        msg = str(err.get("message") or "")
        return code, msg

    # (b) 504 timeout shape: {"error": "Gateway Timeout", "code": "UPSTREAM_TIMEOUT", "message": "..."}
    if "code" in data and isinstance(err, str):
        return str(data["code"]), str(data.get("message") or err)

    # (c) Auth/rate detail dict or FastAPI 422 validation list
    detail = data.get("detail")
    if isinstance(detail, dict):
        code = str(detail.get("error_code") or fallback_code)
        msg = str(detail.get("message") or "")
        return code, msg
    if isinstance(detail, list):
        return "VALIDATION_ERROR", str(detail)[:300]

    # Flat TTS error shape: {"success": false, "message": "...", "status_code": 400}
    if "message" in data:
        return fallback_code, str(data.get("message") or "")

    return fallback_code, str(data)[:300]


async def execute_with_retry(
    send: Callable[[httpx.AsyncClient], Awaitable[httpx.Response]],
    *,
    timeout_s: float,
    retry_delay_s: float,
    error_prefix: str,
    client: httpx.AsyncClient | None = None,
) -> httpx.Response:
    """Execute a Gnani HTTP call with a single retry on transient status codes or transport errors."""

    async def _run(active_client: httpx.AsyncClient) -> httpx.Response:
        last_exc: Exception | None = None
        for attempt in range(2):
            try:
                resp = await send(active_client)
            except (httpx.TimeoutException, httpx.TransportError) as exc:
                last_exc = exc
                if attempt == 0:
                    if retry_delay_s > 0:
                        await asyncio.sleep(retry_delay_s)
                    continue
                raise ApiError(
                    f"{error_prefix}_FAILED",
                    f"{error_prefix} request failed due to a network or timeout error.",
                    502,
                ) from exc

            if resp.status_code in _RETRYABLE_STATUSES and attempt == 0:
                if retry_delay_s > 0:
                    await asyncio.sleep(retry_delay_s)
                continue
            return resp

        raise ApiError(
            f"{error_prefix}_FAILED",
            f"{error_prefix} request failed unexpectedly.",
            502,
        ) from last_exc

    if client is not None:
        return await _run(client)
    async with httpx.AsyncClient(timeout=timeout_s) as owned_client:
        return await _run(owned_client)
