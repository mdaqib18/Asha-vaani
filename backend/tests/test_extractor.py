import asyncio
import json

import httpx
import pytest

from app.core.errors import ApiError
from app.core.settings import Settings
from app.schemas.newborn_visit import (
    DangerSign,
    ExtractedField,
    FieldSource,
    LimbAbnormality,
    LimbLocation,
    NewbornVisitRecord,
)
from app.services.extractor import extract, merge_records


def _settings() -> Settings:
    return Settings(LLM_PROVIDER="gemini", LLM_API_KEY="test-key", LLM_MODEL="gemini-3.5-flash")


def _gemini_json_response(payload_text: str) -> httpx.Response:
    return httpx.Response(
        200,
        json={"candidates": [{"content": {"role": "model", "parts": [{"text": payload_text}]}}]},
    )


def test_extract_spec_section_7_example() -> None:
    llm_out = json.dumps(
        {
            "beneficiary_id": {"value": "1042", "confidence": 0.7},
            "baby_weight_kg": {"value": "2.5 kg", "confidence": 0.9},
            "limb_abnormality": {
                "value": {"present": True, "location": "unspecified"},
                "confidence": 0.8,
            },
            "ambiguities": [],
        }
    )

    def handler(_request: httpx.Request) -> httpx.Response:
        return _gemini_json_response(llm_out)

    async def _run():
        async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
            return await extract(
                "Beneficiary 1042, weight 2.5 kg hai, aur limb problem hai",
                "hi",
                settings=_settings(),
                client=client,
                retry_delay_s=0,
            )

    result = asyncio.run(_run())
    assert result.record.beneficiary_id.value == "1042"
    assert result.record.beneficiary_id.needs_confirmation is True
    assert result.record.baby_weight_kg.value == 2.5
    assert result.record.baby_weight_kg.needs_confirmation is False
    assert result.record.limb_abnormality.value.present is True
    assert result.record.limb_abnormality.value.location == LimbLocation.unspecified
    assert any(a.field == "limb_abnormality.location" for a in result.ambiguities)


def test_extract_normalizes_spoken_hindi_kannada_and_fahrenheit() -> None:
    llm_out = json.dumps(
        {
            "beneficiary_id": {"value": "ek zero chaar do", "confidence": 0.85},
            "baby_weight_kg": {"value": "dhai kilo", "confidence": 0.88},
            "temperature_c": {"value": "98.6 F", "confidence": 0.9},
            "breathing_rate_per_min": {"value": "saath", "confidence": 0.8},
        }
    )

    def handler(_request: httpx.Request) -> httpx.Response:
        return _gemini_json_response(llm_out)

    async def _run():
        async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
            return await extract(
                "ID ek zero chaar do, dhai kilo, 98.6 F, saans saath",
                "hi",
                settings=_settings(),
                client=client,
                retry_delay_s=0,
            )

    res_hi = asyncio.run(_run())
    assert res_hi.record.beneficiary_id.value == "1042"
    assert res_hi.record.baby_weight_kg.value == 2.5
    assert res_hi.record.temperature_c.value == 37.0
    assert res_hi.record.breathing_rate_per_min.value == 60

    # Also test Kannada spoken weight "eradu vare kg"
    llm_kn = json.dumps({"baby_weight_kg": {"value": "eradu vare kg", "confidence": 0.9}})

    async def _run_kn():
        async with httpx.AsyncClient(
            transport=httpx.MockTransport(lambda _r: _gemini_json_response(llm_kn))
        ) as client:
            return await extract("eradu vare kg", "kn", settings=_settings(), client=client, retry_delay_s=0)

    res_kn = asyncio.run(_run_kn())
    assert res_kn.record.baby_weight_kg.value == 2.5


def test_extract_ignores_stray_risk_flags_from_llm() -> None:
    llm_out = json.dumps(
        {
            "baby_weight_kg": {"value": 2.1, "confidence": 0.95},
            "risk_flags": ["llm_invented_flag"],
            "referral_suggested": True,
        }
    )

    async def _run():
        async with httpx.AsyncClient(
            transport=httpx.MockTransport(lambda _r: _gemini_json_response(llm_out))
        ) as client:
            return await extract("weight 2.1 kg", "en", settings=_settings(), client=client, retry_delay_s=0)

    result = asyncio.run(_run())
    assert result.record.baby_weight_kg.value == 2.1
    assert result.record.risk_flags == []
    assert result.record.referral_suggested is False


@pytest.mark.parametrize(
    "bad_first_reply",
    [
        "{not valid json",
        json.dumps({"breastfeeding": {"value": "bottle_fed", "confidence": 0.9}}),
    ],
)
def test_extract_retries_once_on_parse_or_schema_failure(bad_first_reply: str) -> None:
    calls = 0
    seen_prompts: list[str] = []

    def handler(request: httpx.Request) -> httpx.Response:
        nonlocal calls
        calls += 1
        body = json.loads(request.content.decode("utf-8"))
        seen_prompts.append(body["contents"][0]["parts"][0]["text"])
        if calls == 1:
            return _gemini_json_response(bad_first_reply)
        return _gemini_json_response(json.dumps({"breastfeeding": {"value": "exclusive", "confidence": 0.9}}))

    async def _run():
        async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
            return await extract("exclusive breastfeeding", "en", settings=_settings(), client=client, retry_delay_s=0)

    result = asyncio.run(_run())
    assert calls == 2
    assert "Your previous reply was not valid JSON" in seen_prompts[1]
    assert result.record.breastfeeding.value.value == "exclusive"


def test_extract_fails_after_two_parse_failures() -> None:
    calls = 0

    def handler(_request: httpx.Request) -> httpx.Response:
        nonlocal calls
        calls += 1
        return _gemini_json_response("still not json")

    async def _run():
        async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
            await extract("test", "hi", settings=_settings(), client=client, retry_delay_s=0)

    with pytest.raises(ApiError) as exc_info:
        asyncio.run(_run())
    assert calls == 2
    assert exc_info.value.code == "LLM_PARSE_FAILED"
    assert exc_info.value.http_status == 502


def test_extract_strips_markdown_code_fences() -> None:
    fenced = '```json\n{"jaundice": {"value": false, "confidence": 0.9}}\n```'

    async def _run():
        async with httpx.AsyncClient(
            transport=httpx.MockTransport(lambda _r: _gemini_json_response(fenced))
        ) as client:
            return await extract("no jaundice", "en", settings=_settings(), client=client, retry_delay_s=0)

    result = asyncio.run(_run())
    assert result.record.jaundice.value is False


def test_extract_empty_transcript_skips_llm() -> None:
    calls = 0

    def handler(_request: httpx.Request) -> httpx.Response:
        nonlocal calls
        calls += 1
        return _gemini_json_response("{}")

    existing = NewbornVisitRecord(
        beneficiary_id=ExtractedField(value="1042", source=FieldSource.selected)
    )

    async def _run():
        async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
            return await extract("   ", "hi", existing_record=existing, settings=_settings(), client=client)

    result = asyncio.run(_run())
    assert calls == 0
    assert result.record.beneficiary_id.value == "1042"
    assert result.ambiguities == []


def test_merge_records_protects_selected_and_merges_complex_fields() -> None:
    base = NewbornVisitRecord(
        beneficiary_id=ExtractedField(value="1042", source=FieldSource.selected),
        limb_abnormality=ExtractedField(
            value=LimbAbnormality(present=True, location=LimbLocation.unspecified),
            confidence=0.8,
            source=FieldSource.speech,
        ),
        danger_signs=ExtractedField(
            value=[DangerSign.lethargy],
            confidence=0.9,
            source=FieldSource.speech,
        ),
        notes=ExtractedField(value="Baby sleepy", source=FieldSource.speech),
    )
    update = NewbornVisitRecord(
        beneficiary_id=ExtractedField(value="9999", source=FieldSource.speech),
        limb_abnormality=ExtractedField(
            value=LimbAbnormality(present=True, location=LimbLocation.left_leg),
            confidence=0.9,
            source=FieldSource.speech,
        ),
        danger_signs=ExtractedField(
            value=[DangerSign.lethargy, DangerSign.fever],
            confidence=0.85,
            source=FieldSource.speech,
        ),
        notes=ExtractedField(value="Swelling noticed", source=FieldSource.speech),
    )

    merged = merge_records(base, update)
    assert merged.beneficiary_id.value == "1042"
    assert merged.beneficiary_id.source == FieldSource.selected
    assert merged.limb_abnormality.value.location == LimbLocation.left_leg
    assert merged.danger_signs.value == [DangerSign.lethargy, DangerSign.fever]
    assert merged.notes.value == "Baby sleepy; Swelling noticed"


def test_extract_canonicalizes_generic_limb_ambiguity_field() -> None:
    llm_out = json.dumps(
        {
            "limb_abnormality": {
                "value": {"present": True, "location": "unspecified"},
                "confidence": 0.9,
            },
            "ambiguities": [
                {"field": "limb_abnormality", "reason": "Which limb is affected is unclear"}
            ],
        }
    )

    async def _run():
        async with httpx.AsyncClient(
            transport=httpx.MockTransport(lambda _r: _gemini_json_response(llm_out))
        ) as client:
            return await extract("limb problem ide", "kn", settings=_settings(), client=client, retry_delay_s=0)

    result = asyncio.run(_run())
    assert [a.field for a in result.ambiguities] == ["limb_abnormality.location"]
