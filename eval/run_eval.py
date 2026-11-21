"""Evaluation runner for Asha Vaani across transcripts and clean/noisy audio conditions."""

from __future__ import annotations

import argparse
import asyncio
from datetime import datetime, timezone
import json
from pathlib import Path
import sys
import time
from typing import Any

import httpx

REPO_ROOT = Path(__file__).resolve().parent.parent
BACKEND_DIR = REPO_ROOT / "backend"
for path in (str(REPO_ROOT), str(BACKEND_DIR)):
    if path not in sys.path:
        sys.path.insert(0, path)

from app.core.config_loader import VisitTypeConfig, load_visit_config  # noqa: E402
from app.core.errors import ApiError  # noqa: E402
from app.core.settings import Settings, get_settings  # noqa: E402
from app.data.beneficiaries import get_assigned_ids  # noqa: E402
from app.services import extractor, followup, risk_rules, stt_gnani, validator  # noqa: E402
from eval.metrics import (  # noqa: E402
    load_cases,
    record_to_plain_dict,
    score_case,
    write_reports,
)


def _resolve_audio_path(case_id: str, condition: str, audio_root: Path) -> Path:
    if condition == "clean":
        return audio_root / "clean" / f"{case_id}.wav"
    return audio_root / "noisy" / condition / f"{case_id}.wav"


async def evaluate_one(
    case: dict[str, Any],
    condition: str,
    *,
    config: VisitTypeConfig,
    settings: Settings,
    client: httpx.AsyncClient,
    audio_root: Path,
) -> dict[str, Any]:
    """Run one ground-truth case through the pipeline under one condition and score it."""
    case_id = case["id"]
    language = case["language"]
    assigned_ids = get_assigned_ids(case.get("asha_id", "asha_001"))

    stt_s = 0.0
    extract_s = 0.0
    validate_risk_s = 0.0
    followup_s = 0.0
    transcript = case["transcript"]

    try:
        if condition != "transcript":
            audio_path = _resolve_audio_path(case_id, condition, audio_root)
            if not audio_path.is_file():
                raise FileNotFoundError(f"Audio file not found: {audio_path}")
            t0 = time.perf_counter()
            stt_res = await stt_gnani.transcribe(
                audio_path.read_bytes(),
                audio_path.name,
                language,
                settings=settings,
                client=client,
            )
            stt_s = time.perf_counter() - t0
            transcript = stt_res.transcript

        t1 = time.perf_counter()
        extraction = await extractor.extract(
            transcript,
            language,
            "newborn_home_visit",
            settings=settings,
            client=client,
        )
        extract_s = time.perf_counter() - t1

        t2 = time.perf_counter()
        validation = validator.validate(
            extraction.record,
            config,
            assigned_ids=assigned_ids,
        )
        final_record = risk_rules.apply_risk(validation.record, config)
        validate_risk_s = time.perf_counter() - t2

        t3 = time.perf_counter()
        decision = await followup.decide_followup(
            final_record,
            validation.missing_required,
            extraction.ambiguities,
            language=language,
            followup_count=0,
            max_followups=settings.MAX_FOLLOWUPS,
            settings=settings,
            client=client,
        )
        followup_s = time.perf_counter() - t3

        outcome = {
            "transcript": transcript,
            "actual_record": record_to_plain_dict(final_record),
            "actual_risk_flags": list(final_record.risk_flags),
            "actual_referral_suggested": final_record.referral_suggested,
            "actual_validation_flags": [f.model_dump() for f in validation.flags],
            "followup_status": decision.status,
            "followup_source": decision.source,
            "followup_targets": list(decision.target_fields),
            "followup_question": decision.question_text,
            "latencies": {
                "stt_s": stt_s,
                "extract_s": extract_s,
                "validate_risk_s": validate_risk_s,
                "followup_s": followup_s,
                "total_s": stt_s + extract_s + validate_risk_s + followup_s,
            },
        }
    except ApiError as exc:
        outcome = {
            "transcript": transcript if condition == "transcript" else "",
            "error": f"{exc.code}: {exc.message}",
            "latencies": {
                "stt_s": stt_s,
                "extract_s": extract_s,
                "validate_risk_s": validate_risk_s,
                "followup_s": followup_s,
                "total_s": stt_s + extract_s + validate_risk_s + followup_s,
            },
        }
    except Exception as exc:  # noqa: BLE001
        outcome = {
            "transcript": transcript if condition == "transcript" else "",
            "error": f"{type(exc).__name__}: {exc}",
            "latencies": {
                "stt_s": stt_s,
                "extract_s": extract_s,
                "validate_risk_s": validate_risk_s,
                "followup_s": followup_s,
                "total_s": stt_s + extract_s + validate_risk_s + followup_s,
            },
        }

    return score_case(case, condition, outcome)


def _audio_provenance_summary(audio_root: Path, has_audio: bool) -> str:
    if not has_audio:
        return "Transcript-only evaluation (synthetic scripted utterances; no STT audio run included)."
    manifest_path = audio_root / "clean" / "source_manifest.json"
    if not manifest_path.is_file():
        return "Audio clips in eval/audio/clean (source_manifest.json not found) + controlled active-SNR noise mixes."
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    counts: dict[str, int] = {}
    for val in manifest.values():
        counts[str(val)] = counts.get(str(val), 0) + 1
    parts = [f"{v}={k}" for k, v in sorted(counts.items())]
    return (
        "Clean clips ("
        + ", ".join(parts)
        + ") + deterministic 16 kHz active-SNR noise mixes (`market_20db`, `traffic_10db`, `crowd_5db`)."
    )


async def run_evaluation(
    cases: list[dict[str, Any]],
    conditions: list[str],
    *,
    audio_root: Path = Path("eval/audio"),
    output_dir: Path = Path("eval/results"),
    delay_s: float = 0.3,
    merge_existing: bool = False,
    settings: Settings | None = None,
) -> tuple[list[dict[str, Any]], dict[str, Path]]:
    """Run all (condition, case) pairs sequentially and write Markdown/CSV/JSON reports."""
    cfg = settings or get_settings()
    config = load_visit_config("newborn_home_visit")

    new_rows: list[dict[str, Any]] = []
    total_runs = len(cases) * len(conditions)
    step = 0

    async with httpx.AsyncClient(timeout=max(cfg.LLM_TIMEOUT_S, cfg.GNANI_TIMEOUT_S)) as client:
        for cond in conditions:
            for case in cases:
                step += 1
                print(f"[{step}/{total_runs}] condition={cond} case={case['id']} ({case['bucket']})")
                for attempt in range(3):
                    row = await evaluate_one(
                        case,
                        cond,
                        config=config,
                        settings=cfg,
                        client=client,
                        audio_root=audio_root,
                    )
                    err = row.get("error") or ""
                    if attempt < 2 and (
                        err.startswith(("LLM_RATE_LIMITED", "STT_RATE_LIMITED"))
                        or "(UNAVAILABLE)" in err
                    ):
                        print(f"  -> transient API error ({err}), waiting 15s before retry {attempt + 1}/2...")
                        await asyncio.sleep(15.0)
                        continue
                    break
                status = (
                    f"ERR={row['error']}"
                    if row.get("error")
                    else f"fields={row['fields_correct']}/{row['fields_total']} followup={row['followup_appropriate']} total={row['total_s']:.2f}s"
                )
                print(f"  -> {status}")
                new_rows.append(row)
                if delay_s > 0 and step < total_runs:
                    await asyncio.sleep(delay_s)

    rows = list(new_rows)
    if merge_existing:
        raw_path = output_dir / "raw_results.json"
        if raw_path.is_file():
            prev = json.loads(raw_path.read_text(encoding="utf-8"))
            prev_rows = prev.get("rows") or []
            replaced_keys = {(r["condition"], r["case_id"]) for r in new_rows}
            kept = [r for r in prev_rows if (r["condition"], r["case_id"]) not in replaced_keys]
            rows = kept + new_rows

    all_conditions = {r["condition"] for r in rows}
    metadata = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "llm_provider": cfg.LLM_PROVIDER,
        "llm_model": cfg.LLM_MODEL or "unset",
        "stt_model": cfg.GNANI_STT_MODEL,
        "tts_model": cfg.GNANI_TTS_MODEL,
        "audio_provenance": _audio_provenance_summary(
            audio_root,
            has_audio=any(c != "transcript" for c in all_conditions),
        ),
    }
    paths = write_reports(rows, metadata, output_dir)
    return rows, paths


def main(argv: list[str] | None = None) -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")

    parser = argparse.ArgumentParser(description="Run Asha Vaani evaluation harness.")
    parser.add_argument("--ground-truth-dir", type=Path, default=Path("eval/ground_truth"))
    parser.add_argument("--audio-root", type=Path, default=Path("eval/audio"))
    parser.add_argument("--output-dir", type=Path, default=Path("eval/results"))
    parser.add_argument("--mode", choices=["transcript", "audio", "both"], default="transcript")
    parser.add_argument(
        "--conditions",
        default="clean,market_20db,traffic_10db,crowd_5db",
        help="Comma-separated audio conditions for audio/both modes.",
    )
    parser.add_argument("--subset-only", action="store_true")
    parser.add_argument("--ids", default="", help="Comma-separated case IDs to run.")
    parser.add_argument("--buckets", default="", help="Comma-separated buckets to run.")
    parser.add_argument("--limit", type=int, default=0)
    parser.add_argument("--delay-s", type=float, default=0.3)
    parser.add_argument("--merge-existing", action="store_true")
    args = parser.parse_args(argv)

    ids = {x.strip() for x in args.ids.split(",") if x.strip()} or None
    buckets = {x.strip() for x in args.buckets.split(",") if x.strip()} or None
    cases = load_cases(
        args.ground_truth_dir,
        subset_only=args.subset_only,
        ids=ids,
        buckets=buckets,
    )
    if args.limit > 0:
        cases = cases[: args.limit]
    if not cases:
        print("Error: no matching ground-truth cases found.", file=sys.stderr)
        return 1

    audio_conditions = [c.strip() for c in args.conditions.split(",") if c.strip()]
    if args.mode == "transcript":
        conditions = ["transcript"]
    elif args.mode == "audio":
        conditions = audio_conditions
    else:
        conditions = ["transcript", *audio_conditions]

    _, paths = asyncio.run(
        run_evaluation(
            cases,
            conditions,
            audio_root=args.audio_root,
            output_dir=args.output_dir,
            delay_s=args.delay_s,
            merge_existing=args.merge_existing,
        )
    )
    print(f"Report written: {paths['report']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
