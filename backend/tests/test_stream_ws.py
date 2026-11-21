from __future__ import annotations

import asyncio
import json
from collections.abc import AsyncIterator, Iterator
from pathlib import Path

import httpx
import pytest
from fastapi.testclient import TestClient

from app.api.routes import get_http_client, get_stt_stream_factory
from app.core.settings import Settings, get_settings
from app.db.repository import get_v2_repository
from app.db.store import VisitStore, get_store
from app.main import app, get_rate_limiter
from app.services.stt_stream_gnani import (
    PCM_FRAME_BYTES,
    PcmFramePacer,
    StreamTranscriptEvent,
)


class _FakeUpstreamStream:
    def __init__(self, script: list[StreamTranscriptEvent]) -> None:
        self._script = list(script)
        self._queue: asyncio.Queue[StreamTranscriptEvent | None] = asyncio.Queue()
        self.received_frames: list[bytes] = []
        self.finished = False
        self.closed = False
        while self._script and self._script[0].type == "connected":
            self._queue.put_nowait(self._script.pop(0))

    async def send_pcm(self, frame: bytes) -> None:
        self.received_frames.append(frame)
        if self._script:
            await self._queue.put(self._script.pop(0))

    async def finish(self) -> None:
        self.finished = True
        while self._script:
            await self._queue.put(self._script.pop(0))
        await self._queue.put(None)

    async def close(self) -> None:
        self.closed = True
        await self._queue.put(None)

    async def events(self) -> AsyncIterator[StreamTranscriptEvent]:
        while True:
            item = await self._queue.get()
            if item is None:
                break
            yield item


@pytest.fixture
def stream_client(tmp_path: Path) -> Iterator[tuple[TestClient, dict]]:
    db_url = f"sqlite:///{(tmp_path / 'stream.db').as_posix()}"
    store = VisitStore(db_url)
    get_v2_repository(store)
    get_rate_limiter().reset()

    state: dict = {
        "llm_calls": 0,
        "stream_lang": None,
        "upstream": None,
        "raise_on_connect": False,
        "script": [
            StreamTranscriptEvent(type="connected"),
            StreamTranscriptEvent(
                type="partial",
                text="Bacche ka wazan",
                detected_language="hi-IN",
            ),
            StreamTranscriptEvent(
                type="final",
                text="Bacche ka wazan 2.4 kilo hai.",
                utterance_id=1,
                detected_language="hi-IN",
            ),
        ],
    }

    def router(request: httpx.Request) -> httpx.Response:
        if "generativelanguage.googleapis.com" in request.url.host:
            state["llm_calls"] += 1
            extracted = {
                "beneficiary_id": {"value": "1042", "confidence": 0.95},
                "baby_weight_kg": {"value": 2.4, "confidence": 0.96},
                "temperature_c": None,
                "breastfeeding": None,
                "cord_status": None,
                "jaundice": None,
                "limb_abnormality": None,
                "danger_signs": None,
                "ambiguities": [],
            }
            return httpx.Response(
                200,
                json={
                    "candidates": [
                        {
                            "content": {
                                "parts": [{"text": json.dumps(extracted)}]
                            }
                        }
                    ]
                },
            )
        if request.url.host == "api.vachana.ai" and "tts" in request.url.path:
            return httpx.Response(200, content=b"ID3demo-tts", headers={"Content-Type": "audio/mpeg"})
        return httpx.Response(404, json={})

    async def fake_stream_factory(language: str, *, settings=None):
        state["stream_lang"] = language
        if state["raise_on_connect"]:
            raise RuntimeError("Upstream dial failed")
        upstream = _FakeUpstreamStream(state["script"])
        state["upstream"] = upstream
        return upstream

    async_client = httpx.AsyncClient(transport=httpx.MockTransport(router))
    settings = Settings(
        GNANI_API_KEY="test-gnani-key",
        LLM_API_KEY="test-llm-key",
        DATABASE_URL=db_url,
    )
    app.dependency_overrides[get_store] = lambda: store
    app.dependency_overrides[get_settings] = lambda: settings
    app.dependency_overrides[get_http_client] = lambda: async_client
    app.dependency_overrides[get_stt_stream_factory] = lambda: fake_stream_factory
    try:
        with TestClient(app) as client:
            yield client, state
    finally:
        app.dependency_overrides.clear()
        get_rate_limiter().reset()
        store.close()


def test_pcm_frame_pacer_exact_1024_chunks_and_flush() -> None:
    pacer = PcmFramePacer(frame_bytes=PCM_FRAME_BYTES, interval_s=0.032)
    frames_a = pacer.feed(b"\x01" * 1500)
    assert len(frames_a) == 1
    assert len(frames_a[0]) == 1024

    frames_b = pacer.feed(b"\x02" * 600)
    assert len(frames_b) == 1
    assert len(frames_b[0]) == 1024
    assert frames_b[0][:476] == b"\x01" * 476
    assert frames_b[0][476:] == b"\x02" * 548

    padded = pacer.flush()
    assert padded is not None
    assert len(padded) == 1024
    assert padded[:52] == b"\x02" * 52
    assert padded[52:] == b"\x00" * (1024 - 52)
    assert pacer.flush() is None


def test_stream_ws_partial_final_followup_and_auto_language(
    stream_client: tuple[TestClient, dict],
) -> None:
    client, state = stream_client

    with client.websocket_connect("/v1/stream") as ws:
        ws.send_json(
            {
                "type": "start",
                "language": "auto",
                "visit_type": "newborn_home_visit",
                "beneficiary_id": "1042",
                "asha_id": "asha_001",
            }
        )
        # Send 2500 bytes (> 2 full 1024-byte frames, leaving 452 bytes buffered)
        ws.send_bytes(b"\x10\x20" * 1250)

        ev1 = ws.receive_json()
        assert ev1 == {"type": "partial", "text": "Bacche ka wazan"}
        # SPEC_V2 §8.3: do NOT run LLM extraction on partial text
        assert state["llm_calls"] == 0

        ev2 = ws.receive_json()
        assert ev2 == {
            "type": "final",
            "text": "Bacche ka wazan 2.4 kilo hai.",
            "utterance_id": 1,
        }
        assert state["llm_calls"] == 0
        assert state["stream_lang"] == "auto"

        ws.send_json({"type": "stop"})

        ev3 = ws.receive_json()
        assert ev3["type"] == "fields"
        assert ev3["transcript"] == "Bacche ka wazan 2.4 kilo hai."
        assert ev3["record"]["baby_weight_kg"]["value"] == pytest.approx(2.4)
        assert "low_birth_weight" in ev3["risk_flags"]
        assert ev3["status"] == "needs_followup"
        assert state["llm_calls"] == 1

        ev4 = ws.receive_json()
        assert ev4["type"] == "followup"
        assert ev4["question_text"]
        assert ev4["question_audio_url"].startswith("/v1/audio/")

    upstream: _FakeUpstreamStream = state["upstream"]
    assert upstream.finished is True
    assert upstream.closed is True
    # 2 full frames + 1 flushed padded frame = 3 frames of exactly 1024 bytes each
    assert len(upstream.received_frames) == 3
    assert all(len(frame) == 1024 for frame in upstream.received_frames)


def test_stream_ws_upstream_error_returns_stt_stream_failed(
    stream_client: tuple[TestClient, dict],
) -> None:
    client, state = stream_client
    state["raise_on_connect"] = True

    with client.websocket_connect("/v1/stream") as ws:
        ws.send_json(
            {
                "type": "start",
                "language": "hi",
                "visit_type": "newborn_home_visit",
                "beneficiary_id": "1042",
            }
        )
        err = ws.receive_json()
        assert err["type"] == "error"
        assert err["code"] == "STT_STREAM_FAILED"
