import asyncio
import json

import httpx

from app.core.settings import Settings
from app.services.pipeline import process_audio, process_transcript


def _settings() -> Settings:
    return Settings(
        GNANI_API_KEY="test-gnani-key",
        LLM_PROVIDER="gemini",
        LLM_API_KEY="test-gemini-key",
        LLM_MODEL="gemini-2.5-flash",
    )


def _gemini_response(payload: dict) -> httpx.Response:
    text = json.dumps(payload)
    return httpx.Response(
        200,
        json={"candidates": [{"content": {"role": "model", "parts": [{"text": text}]}}]},
    )


def test_pipeline_transcript_spec_section_7_example() -> None:
    payload = {
        "beneficiary_id": {"value": "1042", "confidence": 0.9},
        "baby_weight_kg": {"value": "2.5 kg", "confidence": 0.9},
        "limb_abnormality": {
            "value": {"present": True, "location": "unspecified"},
            "confidence": 0.85,
        },
    }

    async def _run():
        async with httpx.AsyncClient(
            transport=httpx.MockTransport(lambda _r: _gemini_response(payload))
        ) as client:
            return await process_transcript(
                "Beneficiary 1042, weight 2.5 kg hai, aur limb problem hai",
                "hi",
                assigned_ids={"1042"},
                settings=_settings(),
                client=client,
                retry_delay_s=0,
            )

    res = asyncio.run(_run())
    assert res.missing_required == ["temperature_c", "breastfeeding", "cord_status", "jaundice"]
    assert res.record.beneficiary_id.needs_confirmation is True
    assert res.record.baby_weight_kg.needs_confirmation is True
    assert res.record.risk_flags == ["limb_abnormality"]
    assert res.record.referral_suggested is True
    assert any(a.field == "limb_abnormality.location" for a in res.ambiguities)


def test_pipeline_out_of_range_weight_flagged_not_lbw() -> None:
    payload = {
        "beneficiary_id": {"value": "1042", "confidence": 0.95},
        "baby_weight_kg": {"value": "25 kg", "confidence": 0.9},
    }

    async def _run():
        async with httpx.AsyncClient(
            transport=httpx.MockTransport(lambda _r: _gemini_response(payload))
        ) as client:
            return await process_transcript(
                "Beneficiary 1042 weight 25 kg",
                "hi",
                assigned_ids={"1042"},
                settings=_settings(),
                client=client,
                retry_delay_s=0,
            )

    res = asyncio.run(_run())
    assert res.record.baby_weight_kg.value == 25.0
    assert any(f.field == "baby_weight_kg" and f.reason == "out_of_range" for f in res.flags)
    assert "low_birth_weight" not in res.record.risk_flags


def test_pipeline_low_birth_weight_and_fahrenheit_fever_risk() -> None:
    payload = {
        "beneficiary_id": {"value": "1042", "confidence": 0.95},
        "baby_weight_kg": {"value": "2.2 kg", "confidence": 0.92},
        "temperature_c": {"value": "100.4 F", "confidence": 0.92},
        "breastfeeding": {"value": "exclusive", "confidence": 0.95},
        "cord_status": {"value": "clean_dry", "confidence": 0.95},
        "jaundice": {"value": False, "confidence": 0.95},
        "limb_abnormality": {"value": {"present": False}, "confidence": 0.95},
    }

    async def _run():
        async with httpx.AsyncClient(
            transport=httpx.MockTransport(lambda _r: _gemini_response(payload))
        ) as client:
            return await process_transcript(
                "weight 2.2 kg, temp 100.4 F",
                "hi",
                assigned_ids={"1042"},
                settings=_settings(),
                client=client,
                retry_delay_s=0,
            )

    res = asyncio.run(_run())
    assert res.missing_required == []
    assert res.record.temperature_c.value == 38.0
    assert res.record.risk_flags == ["low_birth_weight", "fever"]
    assert res.record.referral_suggested is True


def test_pipeline_audio_end_to_end_mocked() -> None:
    def router(request: httpx.Request) -> httpx.Response:
        host = request.url.host
        if host == "api.vachana.ai":
            return httpx.Response(
                200,
                json={
                    "success": True,
                    "request_id": "stt-1",
                    "transcript": "Beneficiary 1042 weight dhai kilo hai",
                    "model": "prisma-v3.0",
                    "detected_language_code": "hi-IN",
                    "end_to_end_latency": 0.42,
                },
            )
        if host == "generativelanguage.googleapis.com":
            return _gemini_response(
                {
                    "beneficiary_id": {"value": "1042", "confidence": 0.9},
                    "baby_weight_kg": {"value": "dhai kilo", "confidence": 0.9},
                }
            )
        raise AssertionError(f"Unexpected host: {host}")

    async def _run():
        async with httpx.AsyncClient(transport=httpx.MockTransport(router)) as client:
            return await process_audio(
                b"RIFFfakewav",
                "visit.wav",
                "hi",
                assigned_ids={"1042"},
                settings=_settings(),
                client=client,
                retry_delay_s=0,
            )

    res = asyncio.run(_run())
    assert res.transcript == "Beneficiary 1042 weight dhai kilo hai"
    assert res.record.beneficiary_id.value == "1042"
    assert res.record.baby_weight_kg.value == 2.5
    assert res.stt_latency_s == 0.42
    assert res.llm_latency_s is not None
