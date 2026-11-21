from __future__ import annotations

import base64
from collections.abc import Iterator
from datetime import date, timedelta
from pathlib import Path

import httpx
import pytest
from fastapi.testclient import TestClient

from app.api.routes import get_http_client
from app.core.settings import Settings, get_settings
from app.db.store import VisitStore, get_store
from app.main import app
from app.services.beneficiary_extractor import extract_beneficiary_from_transcript


@pytest.fixture
def ben_client(tmp_path: Path) -> Iterator[tuple[TestClient, dict]]:
    state: dict = {
        "stt_transcript": "Naya beneficiary, Sunita, 26 saal, pregnant, 5 mahine, Rampur"
    }

    def router(request: httpx.Request) -> httpx.Response:
        if request.url.host == "api.vachana.ai" and request.url.path == "/stt/v3":
            return httpx.Response(
                200,
                json={
                    "success": True,
                    "request_id": "stt-ben-1",
                    "transcript": state["stt_transcript"],
                    "model": "prisma-v3.0",
                    "detected_language_code": "hi-IN",
                },
            )
        return httpx.Response(404, json={})

    store = VisitStore(f"sqlite:///{(tmp_path / 'ben.db').as_posix()}")
    async_client = httpx.AsyncClient(transport=httpx.MockTransport(router))
    settings = Settings(
        GNANI_API_KEY="test-gnani-key",
        LLM_API_KEY="test-llm-key",
        DATABASE_URL=f"sqlite:///{(tmp_path / 'ben.db').as_posix()}",
    )
    app.dependency_overrides[get_store] = lambda: store
    app.dependency_overrides[get_settings] = lambda: settings
    app.dependency_overrides[get_http_client] = lambda: async_client
    try:
        with TestClient(app) as client:
            yield client, state
    finally:
        app.dependency_overrides.clear()
        store.close()


def test_beneficiary_speech_extractor_multilingual() -> None:
    today = date(2026, 11, 22)
    preg = extract_beneficiary_from_transcript(
        "Naya beneficiary, Sunita, 26 saal, pregnant, 5 mahine, Rampur",
        today=today,
    )
    assert preg.full_name == "Sunita"
    assert preg.beneficiary_type == "pregnant_woman"
    assert preg.sex == "female"
    assert preg.age_years == 26
    assert preg.dob == "2000-11-22"
    assert preg.dob_is_estimated is True
    assert preg.pregnancy_months == 5
    assert preg.edd_date is not None
    assert preg.area_note == "Rampur"

    baby = extract_beneficiary_from_transcript(
        "Newborn baby of Meena, 5 days old, girl, 9876543210",
        today=today,
    )
    assert baby.full_name == "Baby of Meena"
    assert baby.beneficiary_type == "newborn"
    assert baby.sex == "female"
    assert baby.age_days == 5
    assert baby.dob == (today - timedelta(days=5)).isoformat()
    assert baby.phone == "9876543210"


def test_beneficiary_crud_consent_duplicates_and_speak_to_add(
    ben_client: tuple[TestClient, dict],
) -> None:
    client, _state = ben_client

    # Consent is required before saving
    rejected = client.post(
        "/v1/beneficiaries",
        json={
            "worker_id": "asha_001",
            "full_name": "Sunita",
            "beneficiary_type": "pregnant_woman",
            "consent_given": False,
        },
    )
    assert rejected.status_code == 400
    assert rejected.json()["error"]["code"] == "CONSENT_REQUIRED"

    # Valid creation with consent + pregnancy months -> EDD computed + phone masked
    created = client.post(
        "/v1/beneficiaries",
        json={
            "worker_id": "asha_001",
            "full_name": "Smt. Suneeta Devi",
            "beneficiary_type": "pregnant_woman",
            "sex": "female",
            "dob": "2000-05-10",
            "area_note": "Rampur",
            "phone": "9876543210",
            "pregnancy_months": 5,
            "consent_given": True,
            "consent_method": "verbal",
        },
    )
    assert created.status_code == 201
    cbody = created.json()
    assert cbody["full_name"] == "Smt. Suneeta Devi"
    assert cbody["beneficiary_type"] == "pregnant_woman"
    assert cbody["edd_date"] is not None
    assert cbody["phone_masked"] == "••••••3210"
    assert cbody["has_phone"] is True
    assert "9876543210" not in cbody["phone_masked"]
    local_code = cbody["local_code"]

    # List & filter by beneficiary_type
    preg_list = client.get(
        "/v1/beneficiaries",
        params={"asha_id": "asha_001", "beneficiary_type": "pregnant_woman"},
    )
    assert preg_list.status_code == 200
    assert any(item["local_code"] == local_code for item in preg_list.json())

    # Get by local_code & PATCH
    profile = client.get(f"/v1/beneficiaries/{local_code}", params={"worker_id": "asha_001"})
    assert profile.status_code == 200
    assert profile.json()["uuid"] == cbody["uuid"]

    patched = client.patch(
        f"/v1/beneficiaries/{local_code}",
        params={"worker_id": "asha_001"},
        json={"full_name": "Sunita Devi"},
    )
    assert patched.status_code == 200
    assert patched.json()["full_name"] == "Sunita Devi"

    # Duplicate check flags fuzzy + DOB/phone match
    dup = client.post(
        "/v1/beneficiaries/check-duplicate",
        json={
            "worker_id": "asha_001",
            "full_name": "Sunita",
            "dob": "2000-06-01",
            "phone": "9876543210",
        },
    )
    assert dup.status_code == 200
    matches = dup.json()
    assert len(matches) == 1
    assert matches[0]["local_code"] == local_code

    # Speak-to-add endpoint transcribes audio, extracts fields, and screens duplicates
    wav_bytes = base64.b64decode("UklGRiQAAABXQVZFZm10IBAAAAABAAEAQB8AAEAfAAABAAgAZGF0YQAAAAA=")
    spoken = client.post(
        "/v1/beneficiaries/from-audio",
        files={"audio": ("new_ben.wav", wav_bytes, "audio/wav")},
        data={"language": "hi", "worker_id": "asha_001"},
    )
    assert spoken.status_code == 200
    sbody = spoken.json()
    assert sbody["draft"]["full_name"] == "Sunita"
    assert sbody["draft"]["beneficiary_type"] == "pregnant_woman"
    assert sbody["draft"]["pregnancy_months"] == 5
    assert sbody["draft"]["edd_date"] is not None
    assert len(sbody["duplicate_candidates"]) == 1

    # Visits timeline endpoint works cleanly (empty initially)
    timeline = client.get(f"/v1/beneficiaries/{local_code}/visits", params={"worker_id": "asha_001"})
    assert timeline.status_code == 200
    assert timeline.json()["beneficiary_id"] == local_code
    assert timeline.json()["visits"] == []
