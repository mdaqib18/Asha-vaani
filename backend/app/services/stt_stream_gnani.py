"""Gnani Vachana real-time PCM WebSocket Speech-to-Text streaming client (SPEC_V2 §8)."""

from __future__ import annotations

import asyncio
import json
import time
import uuid
from collections.abc import AsyncIterator, Awaitable, Callable
from typing import Any, Protocol

import websockets
from pydantic import BaseModel

from app.core.errors import ApiError
from app.core.settings import Settings, get_settings

# Verified docs.gnani.ai realtime PCM specification:
# 16 kHz, 16-bit signed LE mono -> 512 samples/chunk = 1024 bytes every 32 ms.
PCM_SAMPLE_RATE_HZ = 16000
PCM_FRAME_BYTES = 1024
PCM_FRAME_INTERVAL_S = 0.032

STREAM_LANGUAGE_MAP: dict[str, str] = {
    "hi": "hi-IN",
    "kn": "kn-IN",
    "en": "en-IN",
    "auto": "indic-auto",
}


class StreamTranscriptEvent(BaseModel):
    """Normalized event emitted by Gnani streaming STT."""

    type: str  # "connected" | "partial" | "final" | "error"
    text: str = ""
    utterance_id: int | None = None
    detected_language: str | None = None
    code: str | None = None
    message: str | None = None


class PcmFramePacer:
    """Re-chunks arbitrary PCM byte streams into exact 1024-byte frames paced at 32 ms."""

    def __init__(
        self,
        *,
        frame_bytes: int = PCM_FRAME_BYTES,
        interval_s: float = PCM_FRAME_INTERVAL_S,
        clock: Callable[[], float] = time.monotonic,
    ) -> None:
        self.frame_bytes = frame_bytes
        self.interval_s = interval_s
        self._clock = clock
        self._buf = bytearray()
        self._last_sent_at: float | None = None

    def feed(self, chunk: bytes) -> list[bytes]:
        """Buffer incoming bytes and return zero or more full fixed-size PCM frames."""
        if not chunk:
            return []
        self._buf.extend(chunk)
        frames: list[bytes] = []
        while len(self._buf) >= self.frame_bytes:
            frames.append(bytes(self._buf[: self.frame_bytes]))
            del self._buf[: self.frame_bytes]
        return frames

    def flush(self) -> bytes | None:
        """Zero-pad and emit any remaining buffered PCM bytes at end of stream."""
        if not self._buf:
            return None
        rem = len(self._buf)
        if rem < self.frame_bytes:
            self._buf.extend(b"\x00" * (self.frame_bytes - rem))
        frame = bytes(self._buf[: self.frame_bytes])
        self._buf.clear()
        return frame

    async def _send_with_cadence(
        self,
        frame: bytes,
        sender: Callable[[bytes], Awaitable[None]],
    ) -> None:
        if self.interval_s > 0 and self._last_sent_at is not None:
            elapsed = self._clock() - self._last_sent_at
            remaining = self.interval_s - elapsed
            if remaining > 0:
                await asyncio.sleep(remaining)
        await sender(frame)
        self._last_sent_at = self._clock()

    async def send_paced(
        self,
        chunk: bytes,
        sender: Callable[[bytes], Awaitable[None]],
    ) -> int:
        frames = self.feed(chunk)
        for frame in frames:
            await self._send_with_cadence(frame, sender)
        return len(frames)

    async def flush_paced(
        self,
        sender: Callable[[bytes], Awaitable[None]],
    ) -> int:
        frame = self.flush()
        if frame is None:
            return 0
        await self._send_with_cadence(frame, sender)
        return 1


def parse_gnani_stream_event(raw: str | bytes | dict[str, Any]) -> StreamTranscriptEvent | None:
    """Normalize heterogeneous Gnani WebSocket JSON frames into StreamTranscriptEvent."""
    if isinstance(raw, bytes):
        try:
            raw = raw.decode("utf-8")
        except UnicodeDecodeError:
            return None
    if isinstance(raw, str):
        stripped = raw.strip()
        if not stripped:
            return None
        try:
            data = json.loads(stripped)
        except json.JSONDecodeError:
            return StreamTranscriptEvent(type="partial", text=stripped)
    else:
        data = raw

    if not isinstance(data, dict):
        return None

    ev_type = str(data.get("type") or data.get("event") or "").strip().lower()
    detected = (
        data.get("detected_language_code")
        or data.get("language_code")
        or data.get("detected_language")
    )
    text = str(data.get("text") or data.get("transcript") or "")

    if ev_type == "connected":
        return StreamTranscriptEvent(type="connected")

    if ev_type in ("error", "failed") or data.get("success") is False:
        err_obj = data.get("error")
        msg = (
            str(err_obj.get("message") or "")
            if isinstance(err_obj, dict)
            else str(data.get("message") or err_obj or "Streaming error")
        )
        code = (
            str(err_obj.get("code") or err_obj.get("type") or "STT_STREAM_FAILED")
            if isinstance(err_obj, dict)
            else str(data.get("code") or "STT_STREAM_FAILED")
        )
        return StreamTranscriptEvent(type="error", code=code, message=msg)

    is_final = data.get("is_final")
    if ev_type in ("final", "transcript") and is_final is not False:
        uid_raw = data.get("utterance_id")
        return StreamTranscriptEvent(
            type="final",
            text=text,
            utterance_id=int(uid_raw) if uid_raw is not None else None,
            detected_language=str(detected) if detected else None,
        )

    if ev_type in ("partial", "interim", "processing") or is_final is False:
        return StreamTranscriptEvent(
            type="partial",
            text=text,
            detected_language=str(detected) if detected else None,
        )

    if text:
        return StreamTranscriptEvent(
            type="final" if is_final else "partial",
            text=text,
            detected_language=str(detected) if detected else None,
        )
    return None


def resolve_short_language(detected: str | None, fallback: str = "hi") -> str:
    """Resolve `hi-IN` / `kn-IN` / `en-IN` back into supported app language codes."""
    if not detected:
        return fallback
    short = detected.strip()[:2].lower()
    return short if short in ("hi", "kn", "en") else fallback


class GnaniSttStreamSession(Protocol):
    """Protocol implemented by live Gnani WebSocket streams and test doubles."""

    async def send_pcm(self, frame: bytes) -> None: ...
    async def finish(self) -> None: ...
    async def close(self) -> None: ...
    def events(self) -> AsyncIterator[StreamTranscriptEvent]: ...


class GnaniWebsocketStreamSession:
    """Active WebSocket session connected to Gnani Vachana real-time STT."""

    def __init__(self, ws: Any) -> None:
        self._ws = ws
        self._closed = False

    async def send_pcm(self, frame: bytes) -> None:
        if not self._closed:
            await self._ws.send(frame)

    async def finish(self) -> None:
        if not self._closed:
            await self._ws.send(json.dumps({"event": "stop", "type": "stop"}))

    async def close(self) -> None:
        if not self._closed:
            self._closed = True
            await self._ws.close()

    async def events(self) -> AsyncIterator[StreamTranscriptEvent]:
        try:
            async for raw in self._ws:
                ev = parse_gnani_stream_event(raw)
                if ev is not None:
                    yield ev
        except websockets.exceptions.ConnectionClosed:
            return


async def open_gnani_stream(
    language: str,
    *,
    settings: Settings | None = None,
) -> GnaniSttStreamSession:
    """Open an authenticated WebSocket stream to Gnani real-time STT (`docs.gnani.ai`)."""
    cfg = settings or get_settings()
    if not cfg.GNANI_API_KEY or not cfg.GNANI_API_KEY.strip():
        raise ApiError(
            "STT_NOT_CONFIGURED",
            "Speech-to-text streaming is not configured.",
            503,
        )

    lang_code = STREAM_LANGUAGE_MAP.get(language)
    if lang_code is None:
        raise ApiError(
            "INVALID_LANGUAGE",
            f"Unsupported streaming language code: {language}",
            400,
        )

    headers = {
        "X-API-Key-ID": cfg.GNANI_API_KEY,
        "X-API-Request-ID": str(uuid.uuid4()),
        "language_code": lang_code,
        "model": cfg.GNANI_STT_MODEL,
    }
    try:
        ws = await websockets.connect(
            cfg.GNANI_STT_STREAM_URL,
            additional_headers=headers,
            open_timeout=cfg.GNANI_TIMEOUT_S,
        )
    except Exception as exc:
        raise ApiError(
            "STT_STREAM_FAILED",
            f"Failed to connect to speech stream: {exc}",
            502,
        ) from exc
    return GnaniWebsocketStreamSession(ws)
