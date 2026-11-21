"""Unit tests for the Milestone 8 evaluation dataset, noise mixer, metrics, and runner."""

from __future__ import annotations

import asyncio
import csv
import json
import math
from pathlib import Path
import sys
import wave

import pytest

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from app.core.settings import Settings  # noqa: E402
from app.schemas.newborn_visit import (  # noqa: E402
    Breastfeeding,
    CordStatus,
    DangerSign,
    ExtractedField,
    LimbAbnormality,
    LimbLocation,
    NewbornVisitRecord,
)
from app.services import extractor, followup, stt_gnani  # noqa: E402
from app.services.extractor import Ambiguity, ExtractionResult  # noqa: E402
from app.services.followup import FollowupDecision  # noqa: E402
from app.services.stt_gnani import SttResult  # noqa: E402
from eval.metrics import (  # noqa: E402
    compare_field,
    load_cases,
    record_to_plain_dict,
    score_case,
    score_followup,
    write_reports,
)
from eval.mix_noise import (  # noqa: E402
    compute_active_rms,
    generate_noise,
    mix_at_snr,
    mix_file,
    read_wav_pcm16,
    write_wav_pcm16,
)
from eval.run_eval import run_evaluation  # noqa: E402

GROUND_TRUTH_DIR = REPO_ROOT / "eval" / "ground_truth"


def _make_speech_like_signal(num_samples: int = 32000, sample_rate: int = 16000) -> list[int]:
    """Generate a synthetic 16 kHz amplitude-modulated harmonic speech surrogate."""
    samples: list[int] = []
    for i in range(num_samples):
        t = i / sample_rate
        # Leave 20% silence at beginning/end so active-RMS computation is exercised.
        if t < 0.2 or t > 1.8:
            samples.append(0)
            continue
        env = 0.5 + 0.5 * math.sin(2.0 * math.pi * 4.0 * t)
        carrier = (
            0.6 * math.sin(2.0 * math.pi * 220.0 * t)
            + 0.3 * math.sin(2.0 * math.pi * 440.0 * t)
            + 0.1 * math.sin(2.0 * math.pi * 880.0 * t)
        )
        samples.append(int(round(6000.0 * env * carrier)))
    return samples


def test_ground_truth_dataset_integrity_and_balance() -> None:
    cases = load_cases(GROUND_TRUTH_DIR)
    assert len(cases) == 36

    buckets = {c["bucket"] for c in cases}
    assert buckets == {"hi", "kn", "codemix_hi", "codemix_kn"}

    subset = load_cases(GROUND_TRUTH_DIR, subset_only=True)
    assert len(subset) == 12
    assert sum(1 for c in subset if c["bucket"] == "hi") == 4
    assert sum(1 for c in subset if c["bucket"] == "kn") == 4
    assert sum(1 for c in subset if c["bucket"] in ("codemix_hi", "codemix_kn")) == 4

    bf_vals = {e.value for e in Breastfeeding}
    cord_vals = {e.value for e in CordStatus}
    limb_vals = {e.value for e in LimbLocation}
    danger_vals = {e.value for e in DangerSign}

    for c in cases:
        rec = c["expected_record"]
        if rec.get("breastfeeding") is not None:
            assert rec["breastfeeding"] in bf_vals
        if rec.get("cord_status") is not None:
            assert rec["cord_status"] in cord_vals
        if rec.get("limb_abnormality") is not None:
            loc = rec["limb_abnormality"].get("location")
            if loc is not None:
                assert loc in limb_vals
        for sign in rec.get("danger_signs") or []:
            assert sign in danger_vals


@pytest.mark.parametrize("noise_type", ["market", "traffic", "crowd"])
@pytest.mark.parametrize("target_snr", [20.0, 10.0, 5.0])
def test_noise_mixer_achieves_target_snr(
    tmp_path: Path,
    noise_type: str,
    target_snr: float,
) -> None:
    speech = _make_speech_like_signal()
    noise_a = generate_noise(noise_type, len(speech), sample_rate=16000, seed=123)  # type: ignore[arg-type]
    noise_b = generate_noise(noise_type, len(speech), sample_rate=16000, seed=123)  # type: ignore[arg-type]
    assert noise_a == noise_b  # deterministic for fixed seed

    mixed = mix_at_snr(speech, noise_a, target_snr)
    residual_noise = [m - s for m, s in zip(mixed, speech)]
    speech_rms = compute_active_rms(speech)
    residual_rms = math.sqrt(sum(n * n for n in residual_noise) / len(residual_noise))
    achieved_snr = 20.0 * math.log10(speech_rms / residual_rms)
    assert abs(achieved_snr - target_snr) <= 0.5

    clean_wav = tmp_path / "clean.wav"
    out_wav = tmp_path / f"{noise_type}_{int(target_snr)}db.wav"
    write_wav_pcm16(clean_wav, speech, sample_rate=16000)
    info = mix_file(clean_wav, out_wav, noise_type, target_snr, seed=123)  # type: ignore[arg-type]
    assert info["sample_rate"] == 16000

    with wave.open(str(out_wav), "rb") as wf:
        assert wf.getnchannels() == 1
        assert wf.getsampwidth() == 2
        assert wf.getframerate() == 16000
    loaded, sr = read_wav_pcm16(out_wav)
    assert sr == 16000
    assert len(loaded) == len(speech)


def test_compare_field_and_followup_scoring() -> None:
    assert compare_field("baby_weight_kg", 2.5, 2.54) == (True, "match")
    assert compare_field("baby_weight_kg", 2.5, 2.7) == (False, "mismatch")
    assert compare_field("temperature_c", 37.0, 37.08) == (True, "match")
    assert compare_field("temperature_c", None, 36.8) == (False, "hallucinated")
    assert compare_field("breastfeeding", "exclusive", None) == (False, "missed")
    assert compare_field("danger_signs", [], None) == (True, "match")
    assert compare_field("danger_signs", ["lethargy", "convulsions"], ["convulsions", "lethargy"]) == (
        True,
        "match",
    )
    assert compare_field(
        "limb_abnormality",
        {"present": False, "location": None},
        {"present": False, "location": "unspecified"},
    ) == (True, "match")
    assert compare_field(
        "limb_abnormality",
        {"present": True, "location": "left_leg"},
        {"present": True, "location": "unspecified"},
    ) == (False, "mismatch")

    amb_case = {
        "expected_needs_followup": True,
        "expected_followup_source": "ambiguity",
        "expected_followup_targets": ["limb_abnormality.location"],
    }
    ok, _ = score_followup(
        amb_case,
        "needs_followup",
        "llm_ambiguity",
        ["limb_abnormality.location"],
        {"baby_weight_kg": 3.1, "limb_abnormality": {"present": True, "location": "unspecified"}},
    )
    assert ok is True

    bad_filled, detail = score_followup(
        amb_case,
        "needs_followup",
        "missing_required",
        ["baby_weight_kg"],
        {"baby_weight_kg": 3.1, "limb_abnormality": {"present": True, "location": "unspecified"}},
    )
    assert bad_filled is False
    assert "wrong source" in detail


def test_score_case_and_write_reports(tmp_path: Path) -> None:
    case = load_cases(GROUND_TRUTH_DIR, ids={"hi_01"})[0]
    record = NewbornVisitRecord(
        beneficiary_id=ExtractedField(value="1042"),
        baby_weight_kg=ExtractedField(value=2.8),
        temperature_c=ExtractedField(value=36.8),
        breastfeeding=ExtractedField(value=Breastfeeding.exclusive),
        cord_status=ExtractedField(value=CordStatus.clean_dry),
        jaundice=ExtractedField(value=False),
        breathing_rate_per_min=ExtractedField(value=44),
        limb_abnormality=ExtractedField(value=LimbAbnormality(present=False)),
    )
    row = score_case(
        case,
        "transcript",
        {
            "transcript": case["transcript"],
            "actual_record": record_to_plain_dict(record),
            "actual_risk_flags": [],
            "actual_referral_suggested": False,
            "actual_validation_flags": [],
            "followup_status": "ready_to_confirm",
            "followup_source": "none",
            "followup_targets": [],
            "latencies": {"stt_s": 0.0, "extract_s": 0.4, "validate_risk_s": 0.01, "followup_s": 0.0},
        },
    )
    assert row["fields_correct"] == 9
    assert row["followup_appropriate"] is True

    paths = write_reports(
        [row],
        {"llm_provider": "gemini", "llm_model": "test-model"},
        tmp_path,
    )
    assert paths["report"].is_file()
    assert paths["summary_csv"].is_file()
    assert paths["cases_csv"].is_file()
    md = paths["report"].read_text(encoding="utf-8")
    assert "100.0%" in md

    with paths["summary_csv"].open(encoding="utf-8") as f:
        rows = list(csv.DictReader(f))
    assert len(rows) == 1
    assert rows[0]["field_acc_pct"] == "100.0"


def test_run_evaluation_mocked_pipeline(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    cases = load_cases(GROUND_TRUTH_DIR, ids={"mix_01", "mix_02"})
    clean_dir = tmp_path / "audio" / "clean"
    clean_dir.mkdir(parents=True)
    for c in cases:
        write_wav_pcm16(clean_dir / f"{c['id']}.wav", _make_speech_like_signal(8000), sample_rate=16000)
    (clean_dir / "source_manifest.json").write_text(
        json.dumps({"mix_01": "human_recording", "mix_02": "human_recording"}),
        encoding="utf-8",
    )

    async def fake_transcribe(audio: bytes, filename: str, language: str, **_kwargs):
        cid = Path(filename).stem
        match = next(c for c in cases if c["id"] == cid)
        return SttResult(transcript=match["transcript"], model="mock-prisma")

    async def fake_extract(transcript: str, language: str, visit_type: str = "newborn_home_visit", **_kwargs):
        if "3.0" in transcript:
            return ExtractionResult(
                record=NewbornVisitRecord(
                    beneficiary_id=ExtractedField(value="1042"),
                    baby_weight_kg=ExtractedField(value=3.0),
                    temperature_c=ExtractedField(value=36.8),
                    breastfeeding=ExtractedField(value=Breastfeeding.exclusive),
                    cord_status=ExtractedField(value=CordStatus.clean_dry),
                    jaundice=ExtractedField(value=False),
                    breathing_rate_per_min=ExtractedField(value=45),
                    limb_abnormality=ExtractedField(value=LimbAbnormality(present=False)),
                ),
                ambiguities=[],
            )
        return ExtractionResult(
            record=NewbornVisitRecord(
                beneficiary_id=ExtractedField(value="1042"),
                baby_weight_kg=ExtractedField(value=2.5),
                limb_abnormality=ExtractedField(
                    value=LimbAbnormality(present=True, location=LimbLocation.unspecified)
                ),
            ),
            ambiguities=[Ambiguity(field="limb_abnormality.location", reason="unspecified")],
        )

    async def fake_followup(record, missing_required, ambiguities, **_kwargs):
        if missing_required:
            return FollowupDecision(
                status="needs_followup",
                question_text="Missing required fields",
                target_fields=list(missing_required),
                followup_count=1,
                source="missing_required",
            )
        return FollowupDecision(status="ready_to_confirm", followup_count=0, source="none")

    monkeypatch.setattr(stt_gnani, "transcribe", fake_transcribe)
    monkeypatch.setattr(extractor, "extract", fake_extract)
    monkeypatch.setattr(followup, "decide_followup", fake_followup)

    cfg = Settings(LLM_PROVIDER="gemini", LLM_API_KEY="mock", LLM_MODEL="mock-model", GNANI_API_KEY="mock")
    rows, paths = asyncio.run(
        run_evaluation(
            cases,
            ["transcript", "clean"],
            audio_root=tmp_path / "audio",
            output_dir=tmp_path / "results",
            delay_s=0.0,
            settings=cfg,
        )
    )
    assert len(rows) == 4
    assert all(r["fields_correct"] == 9 for r in rows)
    assert all(r["followup_appropriate"] is True for r in rows)
    assert (tmp_path / "results" / "eval_report.md").is_file()
    assert "human_recording" in paths["report"].read_text(encoding="utf-8")
