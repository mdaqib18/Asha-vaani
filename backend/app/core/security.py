"""Security helpers: signed short-lived session tokens, per-worker rate limits, and PII log redaction."""

from __future__ import annotations

import base64
from collections import deque
import hashlib
import hmac
import json
import logging
import re
import secrets
import threading
import time
from datetime import datetime, timezone
from typing import Any

from app.core.errors import ApiError

_BEARER_RE = re.compile(r"(Bearer\s+)[A-Za-z0-9._~+/=-]+", re.IGNORECASE)
_PHONE_RE = re.compile(r"(?<!\d)(?:\+?91[-\s]?)?[6-9]\d{9}(?!\d)")
_TRANSCRIPT_JSON_RE = re.compile(
    r'("(?:transcript|last_transcript|full_name|phone)"\s*:\s*)"[^"]*"',
    re.IGNORECASE,
)
_TRANSCRIPT_KV_RE = re.compile(
    r"\b(transcript|full_name|phone)=([^\s,;]+)",
    re.IGNORECASE,
)


def _b64_encode(raw: bytes) -> str:
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode("ascii")


def _b64_decode(encoded: str) -> bytes:
    padding = "=" * (-len(encoded) % 4)
    return base64.urlsafe_b64decode((encoded + padding).encode("ascii"))


def issue_session_token(
    worker_id: str,
    *,
    secret: str,
    ttl_seconds: int = 86400,
    now: float | None = None,
) -> tuple[str, str]:
    """Create a short-lived HMAC-SHA256 signed session token and ISO expiration timestamp."""
    issued_at = int(now if now is not None else time.time())
    expires_ts = issued_at + max(60, int(ttl_seconds))
    payload = {
        "sub": worker_id,
        "iat": issued_at,
        "exp": expires_ts,
        "jti": secrets.token_urlsafe(8),
    }
    payload_bytes = json.dumps(payload, separators=(",", ":"), sort_keys=True).encode("utf-8")
    payload_b64 = _b64_encode(payload_bytes)
    sig = hmac.new(secret.encode("utf-8"), payload_b64.encode("ascii"), hashlib.sha256).digest()
    token = f"{payload_b64}.{_b64_encode(sig)}"
    expires_iso = datetime.fromtimestamp(expires_ts, tz=timezone.utc).isoformat()
    return token, expires_iso


def verify_session_token(
    token: str,
    *,
    secret: str,
    now: float | None = None,
) -> dict[str, Any]:
    """Verify HMAC signature and expiration on a session token, raising ApiError(401) on failure."""
    if not token or "." not in token:
        raise ApiError("TOKEN_INVALID", "Malformed session token.", 401)
    parts = token.split(".", 1)
    if len(parts) != 2:
        raise ApiError("TOKEN_INVALID", "Malformed session token.", 401)
    payload_b64, sig_b64 = parts

    expected_sig = hmac.new(
        secret.encode("utf-8"),
        payload_b64.encode("ascii"),
        hashlib.sha256,
    ).digest()
    try:
        actual_sig = _b64_decode(sig_b64)
        payload = json.loads(_b64_decode(payload_b64).decode("utf-8"))
    except Exception as exc:
        raise ApiError("TOKEN_INVALID", "Invalid session token encoding.", 401) from exc

    if not hmac.compare_digest(expected_sig, actual_sig):
        raise ApiError("TOKEN_INVALID", "Invalid session token signature.", 401)

    if not isinstance(payload, dict) or not payload.get("sub"):
        raise ApiError("TOKEN_INVALID", "Invalid session token claims.", 401)

    current = now if now is not None else time.time()
    exp = payload.get("exp")
    if not isinstance(exp, (int, float)) or current >= float(exp):
        raise ApiError("TOKEN_EXPIRED", "Session token expired.", 401)

    return payload


class RateLimiter:
    """Thread-safe 60-second sliding-window per-worker rate limiter."""

    def __init__(self, window_seconds: float = 60.0) -> None:
        self._window_seconds = window_seconds
        self._hits: dict[str, deque[float]] = {}
        self._lock = threading.Lock()

    def check_rate_limit(
        self,
        key: str,
        limit_per_minute: int,
        *,
        now: float | None = None,
    ) -> bool:
        if limit_per_minute <= 0:
            return True
        ts = now if now is not None else time.monotonic()
        cutoff = ts - self._window_seconds
        with self._lock:
            bucket = self._hits.setdefault(key, deque())
            while bucket and bucket[0] <= cutoff:
                bucket.popleft()
            if len(bucket) >= limit_per_minute:
                return False
            bucket.append(ts)
            return True

    def reset(self) -> None:
        with self._lock:
            self._hits.clear()


def redact_sensitive_text(text: str) -> str:
    """Scrub Bearer tokens, phone numbers, and transcript/name fields from log text."""
    cleaned = _BEARER_RE.sub(r"\1[REDACTED]", text)
    cleaned = _PHONE_RE.sub("[PHONE_REDACTED]", cleaned)
    cleaned = _TRANSCRIPT_JSON_RE.sub(r'\1"[REDACTED]"', cleaned)
    cleaned = _TRANSCRIPT_KV_RE.sub(r"\1=[REDACTED]", cleaned)
    return cleaned


class PiiRedactingFilter(logging.Filter):
    """Logging filter preventing transcripts, names, phone numbers, and tokens in logs."""

    def filter(self, record: logging.LogRecord) -> bool:
        rendered = record.getMessage()
        scrubbed = redact_sensitive_text(rendered)
        if scrubbed != rendered:
            record.msg = scrubbed
            record.args = ()
        return True
