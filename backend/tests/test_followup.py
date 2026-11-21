import asyncio
import json

import httpx
import pytest

from app.core.settings import Settings
from app.schemas.newborn_visit import (
    Breastfeeding,
    CordStatus,
    ExtractedField,
    LimbAbnormality,
    LimbLocation,
    NewbornVisitRecord,
)
from app.services.extractor import Ambiguity
from app.services.followup import (
    build_missing_fields_question,
    build_readback_text,
    decide_followup,
)


def _settings(**overrides) -> Settings:
    defaults = {
        "LLM_PROVIDER": "gemini",
        "LLM_API_KEY": "test-key",
        "LLM_MODEL": "gemini-3.5-flash",
    }
    defaults.update(overrides)
    return Settings(**defaults)


def _complete_record(*, limb_location: LimbLocation = LimbLocation.left_leg) -> NewbornVisitRecord:
    return NewbornVisitRecord(
        beneficiary_id=ExtractedField(value="1042"),
        baby_weight_kg=ExtractedField(value=2.5),
        temperature_c=ExtractedField(value=37.0),
        breastfeeding=ExtractedField(value=Breastfeeding.exclusive),
        cord_status=ExtractedField(value=CordStatus.clean_dry),
        jaundice=ExtractedField(value=False),
        limb_abnormality=ExtractedField(
            value=LimbAbnormality(present=True, location=limb_location)
        ),
    )


@pytest.mark.parametrize(
    ("lang", "expected_snippet"),
    [
        ("en", "details are missing"),
        ("hi", "की जानकारी बाकी है"),
        ("kn", "ವಿವರಗಳು ಬಾಕಿ ಇವೆ"),
    ],
)
def test_missing_required_fields_deterministic_no_llm(lang: str, expected_snippet: str) -> None:
    calls = 0

    def handler(_request: httpx.Request) -> httpx.Response:
        nonlocal calls
        calls += 1
        return httpx.Response(200)

    record = NewbornVisitRecord(
        beneficiary_id=ExtractedField(value="1042"),
        baby_weight_kg=ExtractedField(value=2.5),
    )

    async def _run():
        async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
            return await decide_followup(
                record,
                ["temperature_c", "breastfeeding"],
                [Ambiguity(field="limb_abnormality.location", reason="unspecified")],
                language=lang,
                followup_count=0,
                settings=_settings(),
                client=client,
                retry_delay_s=0,
            )

    decision = asyncio.run(_run())
    assert calls == 0
    assert decision.status == "needs_followup"
    assert decision.source == "missing_required"
    assert decision.followup_count == 1
    assert decision.target_fields == ["temperature_c", "breastfeeding"]
    assert decision.question_text is not None
    assert expected_snippet in decision.question_text


def test_build_missing_fields_question_includes_all_fields() -> None:
    q = build_missing_fields_question(["temperature_c", "cord_status", "jaundice"], "en")
    assert "temperature" in q
    assert "cord status" in q
    assert "jaundice check" in q


def test_ambiguity_calls_llm_when_required_fields_filled() -> None:
    calls = 0

    def handler(_request: httpx.Request) -> httpx.Response:
        nonlocal calls
        calls += 1
        reply = json.dumps({"question_text": "बच्चे के किस हाथ या पैर में समस्या है?"})
        return httpx.Response(
            200,
            json={"candidates": [{"content": {"role": "model", "parts": [{"text": reply}]}}]},
        )

    record = _complete_record(limb_location=LimbLocation.unspecified)

    async def _run():
        async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
            return await decide_followup(
                record,
                [],
                [Ambiguity(field="limb_abnormality.location", reason="unspecified")],
                language="hi",
                followup_count=1,
                asked_fields={"temperature_c", "breastfeeding", "cord_status", "jaundice"},
                settings=_settings(),
                client=client,
                retry_delay_s=0,
            )

    decision = asyncio.run(_run())
    assert calls == 1
    assert decision.status == "needs_followup"
    assert decision.source == "llm_ambiguity"
    assert decision.followup_count == 2
    assert decision.target_fields == ["limb_abnormality.location"]
    assert decision.question_text == "बच्चे के किस हाथ या पैर में समस्या है?"


def test_ambiguity_falls_back_on_llm_error() -> None:
    def handler(_request: httpx.Request) -> httpx.Response:
        return httpx.Response(500, json={"error": {"code": 500, "message": "Boom"}})

    record = _complete_record(limb_location=LimbLocation.unspecified)

    async def _run():
        async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
            return await decide_followup(
                record,
                [],
                [Ambiguity(field="limb_abnormality.location", reason="unspecified")],
                language="kn",
                followup_count=0,
                settings=_settings(),
                client=client,
                retry_delay_s=0,
            )

    decision = asyncio.run(_run())
    assert decision.status == "needs_followup"
    assert decision.source == "ambiguity_fallback"
    assert "ಕೈ ಅಥವಾ ಕಾಲಿನಲ್ಲಿ" in decision.question_text


def test_hard_cap_max_followups_returns_ready_to_confirm() -> None:
    record = NewbornVisitRecord(beneficiary_id=ExtractedField(value="1042"))

    decision = asyncio.run(
        decide_followup(
            record,
            ["temperature_c", "breastfeeding"],
            [Ambiguity(field="limb_abnormality.location", reason="unspecified")],
            language="hi",
            followup_count=2,
            max_followups=2,
            settings=_settings(),
            retry_delay_s=0,
        )
    )
    assert decision.status == "ready_to_confirm"
    assert decision.question_text is None
    assert decision.followup_count == 2


def test_already_asked_missing_fields_not_repeated_moves_to_ambiguity() -> None:
    def handler(_request: httpx.Request) -> httpx.Response:
        reply = json.dumps({"question_text": "Which limb is affected?"})
        return httpx.Response(
            200,
            json={"candidates": [{"content": {"role": "model", "parts": [{"text": reply}]}}]},
        )

    record = _complete_record(limb_location=LimbLocation.unspecified)
    record.cord_status = None

    async def _run():
        async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
            return await decide_followup(
                record,
                ["cord_status"],
                [Ambiguity(field="limb_abnormality.location", reason="unspecified")],
                language="en",
                followup_count=1,
                asked_fields={"cord_status"},
                settings=_settings(),
                client=client,
                retry_delay_s=0,
            )

    decision = asyncio.run(_run())
    assert decision.status == "needs_followup"
    assert decision.source == "llm_ambiguity"
    assert decision.target_fields == ["limb_abnormality.location"]


def test_resolved_ambiguity_skipped_no_llm_call() -> None:
    calls = 0

    def handler(_request: httpx.Request) -> httpx.Response:
        nonlocal calls
        calls += 1
        return httpx.Response(200)

    record = _complete_record(limb_location=LimbLocation.left_leg)

    async def _run():
        async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
            return await decide_followup(
                record,
                [],
                [Ambiguity(field="limb_abnormality.location", reason="unspecified")],
                language="hi",
                followup_count=1,
                settings=_settings(),
                client=client,
                retry_delay_s=0,
            )

    decision = asyncio.run(_run())
    assert calls == 0
    assert decision.status == "ready_to_confirm"


def test_build_readback_text_languages_and_missing() -> None:
    full = _complete_record()
    assert "1042" in build_readback_text(full, "en")
    assert "2.5 kg" in build_readback_text(full, "en")
    assert "37.0 degrees Celsius" in build_readback_text(full, "en")

    hi_text = build_readback_text(full, "hi")
    assert "1042" in hi_text and "2.5 किलो" in hi_text and "37.0 डिग्री सेल्सियस" in hi_text

    kn_text = build_readback_text(full, "kn")
    assert "1042" in kn_text and "2.5 ಕೆಜಿ" in kn_text and "37.0 ಡಿಗ್ರಿ ಸೆಲ್ಸಿಯಸ್" in kn_text

    empty = NewbornVisitRecord()
    assert "not recorded" in build_readback_text(empty, "en")
    assert "दर्ज नहीं है" in build_readback_text(empty, "hi")
    assert "ದಾಖಲಾಗಿಲ್ಲ" in build_readback_text(empty, "kn")
