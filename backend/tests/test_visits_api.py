import base64
import json
from collections.abc import Iterator
from pathlib import Path

import httpx
import pytest
from fastapi.testclient import TestClient

from app.api.routes import get_http_client
from app.core.settings import Settings, get_settings
from app.db.store import VisitStore, get_store
from app.main import app


@pytest.fixture
def wired_api(tmp_path: Path) -> Iterator[tuple[TestClient, dict]]:
    """Wire TestClient with temp SQLite VisitStore and mocked STT/TTS/LLM transport."""
    state: dict = {
        "stt_queue": [],
        "llm_queue": [],
        "tts_calls": 0,
        "stt_calls": 0,
        "llm_calls": 0,
    }

    def router(request: httpx.Request) -> httpx.Response:
        host = request.url.host
        path = request.url.path

        if host == "api.vachana.ai" and path == "/stt/v3":
            state["stt_calls"] += 1
            transcript = state["stt_queue"].pop(0) if state["stt_queue"] else ""
            return httpx.Response(
                200,
                json={
                    "success": True,
                    "request_id": f"stt-{state['stt_calls']}",
                    "transcript": transcript,
                    "model": "prisma-v3.0",
                    "detected_language_code": "hi-IN",
                    "end_to_end_latency": 0.25,
                },
            )

        if host == "api.vachana.ai" and path == "/api/v1/tts/inference":
            state["tts_calls"] += 1
            return httpx.Response(
                200,
                content=f"MP3BYTES-{state['tts_calls']}".encode("ascii"),
                headers={"content-type": "audio/mpeg"},
            )

        if host == "generativelanguage.googleapis.com":
            state["llm_calls"] += 1
            reply = state["llm_queue"].pop(0) if state["llm_queue"] else {}
            return httpx.Response(
                200,
                json={
                    "candidates": [
                        {"content": {"role": "model", "parts": [{"text": json.dumps(reply)}]}}
                    ]
                },
            )

        raise AssertionError(f"Unexpected outbound HTTP call: {request.url}")

    db_path = tmp_path / "test_visits.db"
    store = VisitStore(f"sqlite:///{db_path}")
    settings = Settings(
        GNANI_API_KEY="test-gnani-key",
        LLM_PROVIDER="gemini",
        LLM_API_KEY="test-gemini-key",
        LLM_MODEL="gemini-3.5-flash",
        MAX_FOLLOWUPS=2,
    )
    http_client = httpx.AsyncClient(transport=httpx.MockTransport(router))

    app.dependency_overrides[get_store] = lambda: store
    app.dependency_overrides[get_settings] = lambda: settings
    app.dependency_overrides[get_http_client] = lambda: http_client

    try:
        yield TestClient(app), state
    finally:
        app.dependency_overrides.clear()
        store.close()


def test_full_spec_section_7_multiturn_visit_flow(wired_api) -> None:
    client, state = wired_api

    # Turn 1: initial audio -> missing required fields follow-up
    state["stt_queue"].append("Beneficiary 1042, weight 2.5 kg hai, aur limb problem hai")
    state["llm_queue"].append(
        {
            "beneficiary_id": {"value": "1042", "confidence": 0.9},
            "baby_weight_kg": {"value": "2.5 kg", "confidence": 0.9},
            "limb_abnormality": {
                "value": {"present": True, "location": "unspecified"},
                "confidence": 0.85,
            },
        }
    )

    resp1 = client.post(
        "/v1/visits/audio",
        data={"language": "hi", "visit_type": "newborn_home_visit"},
        files={"audio": ("turn1.wav", b"RIFFwav1", "audio/wav")},
    )
    assert resp1.status_code == 200
    body1 = resp1.json()
    session_id = body1["session_id"]
    assert body1["status"] == "needs_followup"
    assert body1["followup"]["followup_count"] == 1
    assert body1["followup"]["target_fields"] == [
        "temperature_c",
        "breastfeeding",
        "cord_status",
        "jaundice",
    ]
    audio_url1 = body1["followup"]["question_audio_url"]
    assert audio_url1.startswith("/v1/audio/")
    audio_resp1 = client.get(audio_url1)
    assert audio_resp1.status_code == 200
    assert audio_resp1.headers["content-type"].startswith("audio/mpeg")
    assert audio_resp1.content == b"MP3BYTES-1"

    # Turn 2: answer missing required fields -> triggers LLM ambiguity follow-up for limb location
    state["stt_queue"].append("Temperature 37 degree, breastfeeding exclusive, cord clean, no jaundice")
    state["llm_queue"].extend(
        [
            {
                "temperature_c": {"value": "37 degree", "confidence": 0.92},
                "breastfeeding": {"value": "exclusive", "confidence": 0.95},
                "cord_status": {"value": "clean_dry", "confidence": 0.95},
                "jaundice": {"value": False, "confidence": 0.95},
            },
            {"question_text": "बच्चे के किस हाथ या पैर में समस्या है?"},
        ]
    )

    resp2 = client.post(
        f"/v1/visits/{session_id}/answer",
        data={"language": "hi"},
        files={"audio": ("turn2.wav", b"RIFFwav2", "audio/wav")},
    )
    assert resp2.status_code == 200
    body2 = resp2.json()
    assert body2["status"] == "needs_followup"
    assert body2["followup"]["followup_count"] == 2
    assert body2["followup"]["target_fields"] == ["limb_abnormality.location"]
    assert body2["followup"]["question_text"] == "बच्चे के किस हाथ या पैर में समस्या है?"
    assert client.get(body2["followup"]["question_audio_url"]).content == b"MP3BYTES-2"

    # Turn 3: clarify limb location -> ready_to_confirm
    state["stt_queue"].append("left leg")
    state["llm_queue"].append(
        {
            "limb_abnormality": {
                "value": {"present": True, "location": "left_leg"},
                "confidence": 0.95,
            }
        }
    )

    resp3 = client.post(
        f"/v1/visits/{session_id}/answer",
        data={"language": "hi"},
        files={"audio": ("turn3.wav", b"RIFFwav3", "audio/wav")},
    )
    assert resp3.status_code == 200
    body3 = resp3.json()
    assert body3["status"] == "ready_to_confirm"
    assert body3["followup"] is None
    assert body3["record"]["limb_abnormality"]["value"]["location"] == "left_leg"

    # Readback confirmation endpoint
    readback_resp = client.get(f"/v1/visits/{session_id}/readback", params={"language": "hi"})
    assert readback_resp.status_code == 200
    readback = readback_resp.json()
    assert "1042" in readback["text"]
    assert "2.5" in readback["text"]
    assert "37.0" in readback["text"]
    assert client.get(readback["audio_url"]).content == b"MP3BYTES-3"

    # Manual PATCH edit -> lowers weight to 2.3 kg -> low_birth_weight risk flag fires
    patch_resp = client.patch(
        f"/v1/visits/{session_id}/record",
        json={"baby_weight_kg": 2.3, "source": "typed"},
    )
    assert patch_resp.status_code == 200
    patched = patch_resp.json()
    assert patched["record"]["baby_weight_kg"]["value"] == 2.3
    assert patched["record"]["baby_weight_kg"]["source"] == "typed"
    assert "low_birth_weight" in patched["risk_flags"]
    assert patched["referral_suggested"] is True

    # Confirm visit (idempotent)
    confirm1 = client.post(f"/v1/visits/{session_id}/confirm")
    assert confirm1.status_code == 200
    visit_id = confirm1.json()["visit_id"]
    assert confirm1.json()["status"] == "saved"

    confirm2 = client.post(f"/v1/visits/{session_id}/confirm")
    assert confirm2.status_code == 200
    assert confirm2.json()["visit_id"] == visit_id

    # List saved visits
    visits_resp = client.get("/v1/visits", params={"asha_id": "asha_001"})
    assert visits_resp.status_code == 200
    visits = visits_resp.json()
    assert len(visits) == 1
    assert visits[0]["visit_id"] == visit_id
    assert visits[0]["beneficiary_id"] == "1042"
    assert "low_birth_weight" in visits[0]["risk_flags"]


def test_preselected_beneficiary_protected_from_speech_overwrite(wired_api) -> None:
    client, state = wired_api
    state["stt_queue"].append("Beneficiary 9999 weight 3.0 kg")
    state["llm_queue"].append(
        {
            "beneficiary_id": {"value": "9999", "confidence": 0.9},
            "baby_weight_kg": {"value": "3.0 kg", "confidence": 0.9},
        }
    )

    resp = client.post(
        "/v1/visits/audio",
        data={"language": "hi", "beneficiary_id": "1043"},
        files={"audio": ("clip.wav", b"RIFFwav", "audio/wav")},
    )
    assert resp.status_code == 200
    rec = resp.json()["record"]
    assert rec["beneficiary_id"]["value"] == "1043"
    assert rec["beneficiary_id"]["source"] == "selected"


def test_empty_transcript_returns_error_retry(wired_api) -> None:
    client, state = wired_api
    state["stt_queue"].append("")

    resp = client.post(
        "/v1/visits/audio",
        data={"language": "hi"},
        files={"audio": ("silence.wav", b"RIFFwav", "audio/wav")},
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["status"] == "error_retry"
    assert body["followup"] is None
    assert state["llm_calls"] == 0


def test_not_found_and_confirmed_conflict_errors(wired_api) -> None:
    client, state = wired_api

    assert client.get("/v1/visits/missing-id").status_code == 404
    assert client.get("/v1/audio/missing-audio").status_code == 404
    assert client.post("/v1/visits/missing-id/confirm").status_code == 404

    state["stt_queue"].append("weight 3 kg")
    state["llm_queue"].append({"baby_weight_kg": {"value": "3 kg", "confidence": 0.9}})
    created = client.post(
        "/v1/visits/audio",
        data={"language": "en"},
        files={"audio": ("a.wav", b"RIFF", "audio/wav")},
    ).json()
    sid = created["session_id"]
    assert client.post(f"/v1/visits/{sid}/confirm").status_code == 200

    patch_confirmed = client.patch(f"/v1/visits/{sid}/record", json={"baby_weight_kg": 3.1})
    assert patch_confirmed.status_code == 409
    assert patch_confirmed.json()["error"]["code"] == "VISIT_ALREADY_CONFIRMED"

    answer_confirmed = client.post(
        f"/v1/visits/{sid}/answer",
        data={"language": "en"},
        files={"audio": ("b.wav", b"RIFF", "audio/wav")},
    )
    assert answer_confirmed.status_code == 409


def test_sync_batch_and_idempotency(wired_api) -> None:
    client, state = wired_api
    state["stt_queue"].append("Beneficiary 1042 weight 3.1 kg")
    state["llm_queue"].append(
        {
            "beneficiary_id": {"value": "1042", "confidence": 0.9},
            "baby_weight_kg": {"value": "3.1 kg", "confidence": 0.9},
        }
    )

    payload = [
        {
            "client_id": "offline-1",
            "audio_base64": base64.b64encode(b"RIFFfakewav").decode("ascii"),
            "filename": "rec1.wav",
            "language": "hi",
        },
        {
            "client_id": "offline-bad",
            "audio_base64": "not-valid-base64!!!",
            "filename": "rec2.wav",
            "language": "hi",
        },
    ]

    resp1 = client.post("/v1/sync", json=payload)
    assert resp1.status_code == 200
    results1 = resp1.json()["results"]
    assert results1[0]["client_id"] == "offline-1"
    assert results1[0]["ok"] is True
    assert results1[0]["result"]["record"]["baby_weight_kg"]["value"] == 3.1
    assert results1[1]["client_id"] == "offline-bad"
    assert results1[1]["ok"] is False
    assert results1[1]["error"]["code"] == "INVALID_AUDIO"

    calls_before = (state["stt_calls"], state["llm_calls"])

    # Re-sending offline-1 must return cached result without re-invoking STT/LLM
    resp2 = client.post("/v1/sync", json=[payload[0]])
    assert resp2.status_code == 200
    results2 = resp2.json()["results"]
    assert results2[0] == results1[0]
    assert (state["stt_calls"], state["llm_calls"]) == calls_before
