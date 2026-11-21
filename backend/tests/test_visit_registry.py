from __future__ import annotations

import base64
from collections.abc import Iterator
from datetime import date, timedelta
from pathlib import Path

import httpx
import pytest
from fastapi.testclient import TestClient

from app.api.routes import get_http_client
from app.core.config_loader import list_visit_configs, load_visit_config
from app.core.settings import Settings, get_settings
from app.db.store import VisitStore, get_store
from app.main import app
from app.services.purpose_engine import (
    detect_purpose_from_text,
    eval_safe_expression,
    evaluate_yaml_risk_rules,
    suggest_visit_purpose,
)


@pytest.fixture
def registry_client(tmp_path: Path) -> Iterator[TestClient]:
    def router(request: httpx.Request) -> httpx.Response:
        if request.url.host == "api.vachana.ai" and request.url.path == "/stt/v3":
            return httpx.Response(
                200,
                json={
                    "success": True,
                    "request_id": "stt-1",
                    "transcript": "beneficiary 1042 weight 3.1 kg temperature 36.8",
                    "model": "prisma-v3.0",
                    "detected_language_code": "en-IN",
                },
            )
        if request.url.host == "generativelanguage.googleapis.com":
            return httpx.Response(
                200,
                json={
                    "candidates": [
                        {
                            "content": {
                                "role": "model",
                                "parts": [
                                    {
                                        "text": (
                                            '{"beneficiary_id": {"value": "1042", "confidence": 0.99},'
                                            ' "baby_weight_kg": {"value": 3.1, "confidence": 0.95},'
                                            ' "temperature_c": {"value": 36.8, "confidence": 0.95}}'
                                        )
                                    }
                                ],
                            }
                        }
                    ]
                },
            )
        return httpx.Response(404, json={})

    store = VisitStore(f"sqlite:///{(tmp_path / 'reg.db').as_posix()}")
    async_client = httpx.AsyncClient(transport=httpx.MockTransport(router))
    test_settings = Settings(
        GNANI_API_KEY="test-gnani",
        LLM_API_KEY="test-llm",
        DATABASE_URL="sqlite:///:memory:",
    )
    app.dependency_overrides[get_store] = lambda: store
    app.dependency_overrides[get_settings] = lambda: test_settings
    app.dependency_overrides[get_http_client] = lambda: async_client
    try:
        with TestClient(app) as client:
            yield client
    finally:
        app.dependency_overrides.clear()
        store.close()


def test_registry_discovers_all_yaml_visit_types() -> None:
    configs = list_visit_configs()
    codes = {c.effective_code for c in configs}
    assert {"newborn_home_visit", "anc_visit", "general_illness", "ncd_screening"}.issubset(
        codes
    )
    anc = load_visit_config("anc_visit")
    assert anc.schema_version == 1
    assert anc.name["en"] == "Antenatal check (ANC)"
    assert "pregnant_woman" in anc.applies_to


def test_safe_ast_rule_evaluator_for_new_purposes() -> None:
    anc = load_visit_config("anc_visit")
    flags, referral = evaluate_yaml_risk_rules(
        {"bp_systolic": 146, "bp_diastolic": 94, "hb_g_dl": 9.8, "bleeding": False},
        anc,
    )
    assert "high_blood_pressure" in flags
    assert "anaemia" in flags
    assert referral is True

    # Out-of-range systolic BP must not trigger blood pressure rules falsely.
    clean_flags, clean_referral = evaluate_yaml_risk_rules(
        {"bp_systolic": 999, "bp_diastolic": 78, "hb_g_dl": 12.1},
        anc,
    )
    assert clean_flags == []
    assert clean_referral is False

    ncd = load_visit_config("ncd_screening")
    ncd_flags, ncd_referral = evaluate_yaml_risk_rules(
        {"bp_systolic": 120, "bp_diastolic": 80, "random_blood_sugar_mg_dl": 225},
        ncd,
    )
    assert "high_blood_sugar" in ncd_flags
    assert ncd_referral is True

    illness = load_visit_config("general_illness")
    ill_flags, ill_referral = evaluate_yaml_risk_rules(
        {"temperature_c": 38.4, "duration_days": 4},
        illness,
    )
    assert "fever" in ill_flags
    assert "persistent_fever" in ill_flags
    assert ill_referral is True

    with pytest.raises(ValueError):
        eval_safe_expression("__import__('os').system('echo hacked')", {})


def test_purpose_suggestion_and_voice_keyword_detection() -> None:
    today = date(2026, 11, 22)
    baby_dob = today - timedelta(days=6)
    s_newborn = suggest_visit_purpose(
        beneficiary_type="newborn",
        dob=baby_dob,
        today=today,
    )
    assert s_newborn.suggested_code == "newborn_home_visit"
    assert "day 7" in s_newborn.reason["en"]
    assert "general_illness" in s_newborn.other_codes

    # Newborn older than 42 days falls back from HBNC to general illness
    older_baby = suggest_visit_purpose(
        beneficiary_type="newborn",
        dob=today - timedelta(days=50),
        today=today,
    )
    assert older_baby.suggested_code == "general_illness"

    s_preg = suggest_visit_purpose(beneficiary_type="pregnant_woman", today=today)
    assert s_preg.suggested_code == "anc_visit"

    s_adult = suggest_visit_purpose(beneficiary_type="adult", today=today)
    assert s_adult.suggested_code == "ncd_screening"

    assert detect_purpose_from_text("Do BP check today") is not None
    assert detect_purpose_from_text("Do BP check today").code == "ncd_screening"
    assert detect_purpose_from_text("गर्भवती महिला की जांच").code == "anc_visit"
    assert detect_purpose_from_text("ಮಗುವಿಗೆ ಜ್ವರ ಇದೆ").code == "general_illness"


def test_visit_registry_endpoints_and_audio_schema_version(registry_client: TestClient) -> None:
    resp = registry_client.get("/v1/visit-types")
    assert resp.status_code == 200
    items = resp.json()
    assert len(items) >= 4
    by_code = {item["code"]: item for item in items}
    assert by_code["anc_visit"]["schema_version"] == 1

    preg_only = registry_client.get("/v1/visit-types", params={"beneficiary_type": "pregnant_woman"})
    assert preg_only.status_code == 200
    preg_codes = {item["code"] for item in preg_only.json()}
    assert "anc_visit" in preg_codes
    assert "general_illness" in preg_codes

    suggested = registry_client.get(
        "/v1/beneficiaries/1042/suggested-purpose",
        params={"beneficiary_type": "newborn", "spoken_hint": "BP check"},
    )
    assert suggested.status_code == 200
    body = suggested.json()
    assert body["suggested_code"] == "newborn_home_visit"
    assert body["detected_purpose"]["code"] == "ncd_screening"

    wav_bytes = base64.b64decode("UklGRiQAAABXQVZFZm10IBAAAAABAAEAQB8AAEAfAAABAAgAZGF0YQAAAAA=")
    upload = registry_client.post(
        "/v1/visits/audio",
        files={"audio": ("visit.wav", wav_bytes, "audio/wav")},
        data={"language": "en", "visit_type": "newborn_home_visit", "asha_id": "asha_001"},
    )
    assert upload.status_code == 200
    turn = upload.json()
    assert turn["visit_type_code"] == "newborn_home_visit"
    assert turn["schema_version"] == 1
