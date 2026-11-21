"""Provider-configurable LLM client for structured JSON generation."""

from __future__ import annotations

import time

import httpx
from pydantic import BaseModel

from app.core.errors import ApiError
from app.core.settings import Settings, get_settings
from app.services.gnani_common import execute_with_retry


class LlmResponse(BaseModel):
    """Response wrapper returned by the LLM client."""

    text: str
    model: str
    latency_s: float


def _parse_gemini_error(resp: httpx.Response) -> tuple[str, str]:
    """Extract (status_code_name, message) from a Gemini REST error body without raising."""
    fallback = f"HTTP_{resp.status_code}"
    try:
        data = resp.json()
    except Exception:
        text = (resp.text or "").strip()
        return fallback, text[:250] if text else f"HTTP {resp.status_code}"

    if isinstance(data, dict):
        err = data.get("error")
        if isinstance(err, dict):
            status = str(err.get("status") or err.get("code") or fallback)
            msg = str(err.get("message") or "")
            return status, msg[:250]
    return fallback, str(data)[:250]


def _extract_gemini_text(payload: dict) -> str:
    """Extract generated text from Gemini response, skipping thinking parts."""
    candidates = payload.get("candidates")
    if not isinstance(candidates, list) or not candidates:
        return ""
    content = candidates[0].get("content") if isinstance(candidates[0], dict) else None
    parts = content.get("parts") if isinstance(content, dict) else None
    if not isinstance(parts, list):
        return ""

    text_chunks = [
        part["text"]
        for part in parts
        if isinstance(part, dict)
        and part.get("thought") is not True
        and isinstance(part.get("text"), str)
    ]
    return "".join(text_chunks).strip()


async def generate_json(
    system_prompt: str,
    user_prompt: str,
    *,
    settings: Settings | None = None,
    client: httpx.AsyncClient | None = None,
    retry_delay_s: float = 1.0,
) -> LlmResponse:
    """Generate a JSON string response from the configured LLM provider."""
    cfg = settings or get_settings()
    if not cfg.LLM_API_KEY or not cfg.LLM_API_KEY.strip():
        raise ApiError(
            "LLM_NOT_CONFIGURED",
            "LLM service is not configured.",
            503,
        )

    if not cfg.LLM_MODEL or not cfg.LLM_MODEL.strip():
        raise ApiError(
            "LLM_NOT_CONFIGURED",
            "LLM_MODEL is not configured in .env.",
            503,
        )

    provider = (cfg.LLM_PROVIDER or "").strip().lower()
    if provider != "gemini":
        raise ApiError(
            "LLM_UNSUPPORTED_PROVIDER",
            f"Unsupported LLM provider: {cfg.LLM_PROVIDER}",
            503,
        )

    model_name = cfg.LLM_MODEL.strip()
    url = f"{cfg.LLM_BASE_URL.rstrip('/')}/models/{model_name}:generateContent"
    headers = {
        "Content-Type": "application/json",
        "x-goog-api-key": cfg.LLM_API_KEY,
    }
    body = {
        "systemInstruction": {"parts": [{"text": system_prompt}]},
        "contents": [{"role": "user", "parts": [{"text": user_prompt}]}],
        "generationConfig": {
            "temperature": 0.0,
            "responseMimeType": "application/json",
        },
    }

    t0 = time.perf_counter()
    resp = await execute_with_retry(
        lambda c: c.post(url, headers=headers, json=body),
        timeout_s=cfg.LLM_TIMEOUT_S,
        retry_delay_s=retry_delay_s,
        error_prefix="LLM",
        client=client,
    )
    latency_s = round(time.perf_counter() - t0, 3)

    if resp.status_code != 200:
        err_status, err_msg = _parse_gemini_error(resp)
        if resp.status_code in (401, 403):
            raise ApiError(
                "LLM_AUTH_FAILED",
                f"LLM authorization failed ({err_status}).",
                502,
            )
        if resp.status_code == 429:
            raise ApiError(
                "LLM_RATE_LIMITED",
                f"LLM service is temporarily busy ({err_status}). Please retry.",
                503,
            )
        raise ApiError(
            "LLM_FAILED",
            f"LLM request failed ({err_status}): {err_msg}",
            502,
        )

    try:
        payload = resp.json()
    except Exception as exc:
        raise ApiError("LLM_FAILED", "LLM returned invalid JSON envelope.", 502) from exc

    if not isinstance(payload, dict):
        raise ApiError("LLM_FAILED", "LLM returned unexpected response format.", 502)

    text = _extract_gemini_text(payload)
    if not text:
        raise ApiError("LLM_FAILED", "LLM returned an empty response.", 502)

    return LlmResponse(text=text, model=model_name, latency_s=latency_s)
