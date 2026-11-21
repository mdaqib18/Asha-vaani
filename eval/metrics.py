"""Scoring metrics, CSV export, and Markdown report generation for Asha Vaani eval."""

from __future__ import annotations

import csv
from datetime import datetime, timezone
import json
import math
from pathlib import Path
from statistics import mean
from typing import Any

EVAL_FIELDS: tuple[str, ...] = (
    "beneficiary_id",
    "baby_weight_kg",
    "temperature_c",
    "breastfeeding",
    "cord_status",
    "jaundice",
    "breathing_rate_per_min",
    "limb_abnormality",
    "danger_signs",
)

NUMBER_FIELDS: tuple[str, ...] = (
    "baby_weight_kg",
    "temperature_c",
    "breathing_rate_per_min",
)

CONDITION_ORDER: tuple[str, ...] = (
    "transcript",
    "clean",
    "market_20db",
    "traffic_10db",
    "crowd_5db",
)

_VALID_LANGUAGES = {"hi", "kn", "en"}


def _unwrap_enum(val: Any) -> Any:
    return val.value if hasattr(val, "value") else val


def load_cases(
    ground_truth_dir: Path,
    *,
    subset_only: bool = False,
    ids: set[str] | None = None,
    buckets: set[str] | None = None,
) -> list[dict[str, Any]]:
    """Load and validate ground-truth evaluation cases from JSON files."""
    if not ground_truth_dir.is_dir():
        raise FileNotFoundError(f"Ground truth directory not found: {ground_truth_dir}")

    cases: list[dict[str, Any]] = []
    seen_ids: set[str] = set()

    for json_path in sorted(ground_truth_dir.glob("*.json")):
        raw = json.loads(json_path.read_text(encoding="utf-8"))
        items = raw if isinstance(raw, list) else [raw]
        for item in items:
            if not isinstance(item, dict):
                raise ValueError(f"Invalid case entry in {json_path}: expected object")
            case_id = item.get("id")
            if not isinstance(case_id, str) or not case_id.strip():
                raise ValueError(f"Case missing string id in {json_path}")
            if case_id in seen_ids:
                raise ValueError(f"Duplicate case id '{case_id}' found in {json_path}")
            seen_ids.add(case_id)

            lang = item.get("language")
            if lang not in _VALID_LANGUAGES:
                raise ValueError(f"Case '{case_id}' has unsupported language '{lang}'")

            transcript = item.get("transcript")
            if not isinstance(transcript, str) or not transcript.strip():
                raise ValueError(f"Case '{case_id}' missing non-empty transcript")

            if "expected_record" not in item or not isinstance(item["expected_record"], dict):
                raise ValueError(f"Case '{case_id}' missing expected_record")

            if subset_only and not bool(item.get("audio_subset", False)):
                continue
            if ids is not None and case_id not in ids:
                continue
            if buckets is not None and item.get("bucket") not in buckets:
                continue
            cases.append(item)

    return cases


def record_to_plain_dict(record: Any) -> dict[str, Any]:
    """Convert a NewbornVisitRecord (or serialized dict) into plain comparable field values."""
    if record is None:
        return {field: None for field in EVAL_FIELDS}

    if hasattr(record, "model_dump"):
        data = record.model_dump(mode="json")
    elif isinstance(record, dict):
        data = record
    else:
        raise TypeError(f"Unsupported record type: {type(record)}")

    plain: dict[str, Any] = {}
    for field in EVAL_FIELDS:
        entry = data.get(field)
        if isinstance(entry, dict) and "value" in entry:
            val = entry.get("value")
        else:
            val = entry

        if field == "limb_abnormality" and isinstance(val, dict):
            plain[field] = {
                "present": bool(val.get("present")),
                "location": _unwrap_enum(val.get("location")),
            }
        elif field == "danger_signs" and isinstance(val, list):
            plain[field] = [_unwrap_enum(v) for v in val]
        else:
            plain[field] = _unwrap_enum(val)
    return plain


def _norm_limb(val: Any) -> dict[str, Any] | None:
    if val is None:
        return None
    if hasattr(val, "model_dump"):
        val = val.model_dump(mode="json")
    if isinstance(val, dict):
        return {
            "present": bool(val.get("present")),
            "location": _unwrap_enum(val.get("location")),
        }
    return None


def compare_field(field_name: str, expected: Any, actual: Any) -> tuple[bool, str]:
    """Compare one expected vs actual field value and return (is_match, status)."""
    if field_name == "danger_signs":
        exp_set = {_unwrap_enum(v) for v in (expected or [])}
        act_set = {_unwrap_enum(v) for v in (actual or [])}
        if exp_set == act_set:
            return True, "match"
        if not exp_set and act_set:
            return False, "hallucinated"
        if exp_set and not act_set:
            return False, "missed"
        return False, "mismatch"

    if field_name == "limb_abnormality":
        exp_limb = _norm_limb(expected)
        act_limb = _norm_limb(actual)
        if exp_limb is None:
            return (True, "match") if act_limb is None else (False, "hallucinated")
        if act_limb is None:
            return False, "missed"
        if exp_limb["present"] is False:
            return (True, "match") if act_limb["present"] is False else (False, "mismatch")
        if act_limb["present"] is True and act_limb["location"] == exp_limb.get("location"):
            return True, "match"
        return False, "mismatch"

    exp_val = _unwrap_enum(expected)
    act_val = _unwrap_enum(actual)

    if exp_val is None:
        return (True, "match") if act_val is None else (False, "hallucinated")
    if act_val is None:
        return False, "missed"

    if field_name == "baby_weight_kg":
        try:
            ok = abs(float(act_val) - float(exp_val)) <= 0.05
        except (TypeError, ValueError):
            ok = False
        return (True, "match") if ok else (False, "mismatch")

    if field_name == "temperature_c":
        try:
            ok = abs(float(act_val) - float(exp_val)) <= 0.1
        except (TypeError, ValueError):
            ok = False
        return (True, "match") if ok else (False, "mismatch")

    if field_name == "breathing_rate_per_min":
        try:
            ok = isinstance(act_val, (int, float)) and not isinstance(act_val, bool) and int(round(float(act_val))) == int(exp_val)
        except (TypeError, ValueError):
            ok = False
        return (True, "match") if ok else (False, "mismatch")

    if field_name == "jaundice":
        ok = isinstance(act_val, bool) and act_val is bool(exp_val)
        return (True, "match") if ok else (False, "mismatch")

    return ((True, "match") if str(act_val) == str(exp_val) else (False, "mismatch"))


def score_followup(
    case: dict[str, Any],
    decision_status: str,
    decision_source: str,
    target_fields: list[str],
    actual_record: dict[str, Any],
) -> tuple[bool, str]:
    """Judge follow-up appropriateness (asked iff needed, right targets, no already-filled ask)."""
    expected_needs = bool(case.get("expected_needs_followup", False))
    expected_source = case.get("expected_followup_source", "none")
    expected_targets = set(case.get("expected_followup_targets") or [])
    actual_targets = set(target_fields or [])

    if not expected_needs:
        if decision_status == "ready_to_confirm":
            return True, "ok (ready_to_confirm)"
        return False, f"unnecessary follow-up ({decision_source}: {sorted(actual_targets)})"

    if decision_status != "needs_followup":
        return False, f"missed follow-up (got {decision_status}, expected {expected_source})"

    if expected_source == "missing_required":
        if decision_source != "missing_required":
            return False, f"wrong source '{decision_source}', expected 'missing_required'"
    elif expected_source == "ambiguity":
        if decision_source not in ("llm_ambiguity", "ambiguity_fallback"):
            return False, f"wrong source '{decision_source}', expected ambiguity follow-up"

    if expected_targets and not expected_targets.issubset(actual_targets):
        missing_targets = sorted(expected_targets - actual_targets)
        return False, f"missed target field(s): {missing_targets}"

    # Verify we did not ask about an already cleanly filled scalar/specified field.
    for target in target_fields:
        base = target.split(".", 1)[0]
        if base == "limb_abnormality":
            limb = _norm_limb(actual_record.get("limb_abnormality"))
            if limb is not None:
                loc = limb.get("location")
                if limb["present"] is False or loc not in (None, "unspecified"):
                    return False, f"asked already-resolved field '{target}'"
        elif actual_record.get(base) is not None:
            return False, f"asked already-filled field '{target}'"

    return True, f"ok ({decision_source})"


def score_case(case: dict[str, Any], condition: str, outcome: dict[str, Any]) -> dict[str, Any]:
    """Score a single case execution under a given condition."""
    expected_record = case["expected_record"]
    error = outcome.get("error")
    actual_record = outcome.get("actual_record") or {f: None for f in EVAL_FIELDS}

    latencies = outcome.get("latencies") or {}
    stt_s = float(latencies.get("stt_s", 0.0) or 0.0)
    extract_s = float(latencies.get("extract_s", 0.0) or 0.0)
    validate_risk_s = float(latencies.get("validate_risk_s", 0.0) or 0.0)
    followup_s = float(latencies.get("followup_s", 0.0) or 0.0)
    total_s = float(latencies.get("total_s", stt_s + extract_s + validate_risk_s + followup_s) or 0.0)

    field_results: dict[str, dict[str, Any]] = {}
    fields_correct = 0
    hallucination_count = 0
    numbers_correct = 0
    numbers_total = 0

    for field in EVAL_FIELDS:
        exp_val = expected_record.get(field)
        act_val = actual_record.get(field)
        if error:
            ok, status = False, "error"
        else:
            ok, status = compare_field(field, exp_val, act_val)

        if ok:
            fields_correct += 1
        if status == "hallucinated":
            hallucination_count += 1
        if field in NUMBER_FIELDS and exp_val is not None:
            numbers_total += 1
            if ok:
                numbers_correct += 1

        field_results[field] = {
            "match": ok,
            "status": status,
            "expected": exp_val,
            "actual": act_val,
        }

    id_expected = expected_record.get("beneficiary_id") is not None
    id_correct = bool(field_results["beneficiary_id"]["match"]) if id_expected else True

    expected_risks = set(case.get("expected_risk_flags") or [])
    actual_risks = set(outcome.get("actual_risk_flags") or [])
    expected_referral = bool(case.get("expected_referral_suggested", False))
    actual_referral = bool(outcome.get("actual_referral_suggested", False))

    expected_vflags = {
        (item["field"], item["reason"]) for item in (case.get("expected_validation_flags") or [])
    }
    actual_vflags = {
        (item["field"], item["reason"])
        for item in (outcome.get("actual_validation_flags") or [])
        if item.get("reason") != "missing_required"
    }

    if error:
        risk_flags_exact = False
        referral_correct = False
        validation_flags_match = False
        followup_ok, followup_detail = False, f"error: {error}"
    else:
        risk_flags_exact = actual_risks == expected_risks
        referral_correct = actual_referral == expected_referral
        validation_flags_match = actual_vflags == expected_vflags
        followup_ok, followup_detail = score_followup(
            case,
            str(outcome.get("followup_status") or "ready_to_confirm"),
            str(outcome.get("followup_source") or "none"),
            list(outcome.get("followup_targets") or []),
            actual_record,
        )

    return {
        "case_id": case["id"],
        "condition": condition,
        "language": case["language"],
        "bucket": case.get("bucket", case["language"]),
        "asha_id": case.get("asha_id", "asha_001"),
        "audio_subset": bool(case.get("audio_subset", False)),
        "expected_transcript": case["transcript"],
        "actual_transcript": outcome.get("transcript", ""),
        "error": error,
        "fields_correct": fields_correct,
        "fields_total": len(EVAL_FIELDS),
        "hallucination_count": hallucination_count,
        "id_correct": id_correct,
        "numbers_correct": numbers_correct,
        "numbers_total": numbers_total,
        "risk_flags_exact": risk_flags_exact,
        "referral_correct": referral_correct,
        "validation_flags_match": validation_flags_match,
        "followup_appropriate": followup_ok,
        "followup_detail": followup_detail,
        "field_results": field_results,
        "expected_risk_flags": sorted(expected_risks),
        "actual_risk_flags": sorted(actual_risks),
        "expected_validation_flags": sorted(expected_vflags),
        "actual_validation_flags": sorted(actual_vflags),
        "followup_question": outcome.get("followup_question"),
        "stt_s": round(stt_s, 3),
        "extract_s": round(extract_s, 3),
        "validate_risk_s": round(validate_risk_s, 3),
        "followup_s": round(followup_s, 3),
        "total_s": round(total_s, 3),
    }


def _pct(num: int, den: int) -> float:
    return (100.0 * num / den) if den > 0 else 0.0


def _p95(values: list[float]) -> float:
    if not values:
        return 0.0
    ordered = sorted(values)
    idx = max(0, min(len(ordered) - 1, math.ceil(0.95 * len(ordered)) - 1))
    return ordered[idx]


def aggregate_rows(rows: list[dict[str, Any]]) -> dict[str, Any]:
    """Compute aggregate metrics across a list of scored case rows."""
    n = len(rows)
    if n == 0:
        return {"cases": 0}

    errors = sum(1 for r in rows if r.get("error"))
    fields_correct = sum(r["fields_correct"] for r in rows)
    fields_total = sum(r["fields_total"] for r in rows)
    hallucinations = sum(r["hallucination_count"] for r in rows)
    id_correct = sum(1 for r in rows if r["id_correct"])
    numbers_correct = sum(r["numbers_correct"] for r in rows)
    numbers_total = sum(r["numbers_total"] for r in rows)
    risk_exact = sum(1 for r in rows if r["risk_flags_exact"])
    referral_correct = sum(1 for r in rows if r["referral_correct"])
    validation_exact = sum(1 for r in rows if r["validation_flags_match"])
    followup_ok = sum(1 for r in rows if r["followup_appropriate"])

    per_field_acc: dict[str, float] = {}
    for field in EVAL_FIELDS:
        matched = sum(1 for r in rows if r["field_results"][field]["match"])
        per_field_acc[field] = round(_pct(matched, n), 1)

    non_error = [r for r in rows if not r.get("error")] or rows
    stt_vals = [float(r["stt_s"]) for r in non_error]
    ext_vals = [float(r["extract_s"]) for r in non_error]
    val_vals = [float(r["validate_risk_s"]) for r in non_error]
    fup_vals = [float(r["followup_s"]) for r in non_error]
    tot_vals = [float(r["total_s"]) for r in non_error]

    return {
        "cases": n,
        "errors": errors,
        "field_acc_pct": round(_pct(fields_correct, fields_total), 1),
        "fields_correct": fields_correct,
        "fields_total": fields_total,
        "id_acc_pct": round(_pct(id_correct, n), 1),
        "id_correct": id_correct,
        "number_acc_pct": round(_pct(numbers_correct, numbers_total), 1),
        "numbers_correct": numbers_correct,
        "numbers_total": numbers_total,
        "hallucinations": hallucinations,
        "risk_acc_pct": round(_pct(risk_exact, n), 1),
        "referral_acc_pct": round(_pct(referral_correct, n), 1),
        "validation_acc_pct": round(_pct(validation_exact, n), 1),
        "followup_acc_pct": round(_pct(followup_ok, n), 1),
        "followup_correct": followup_ok,
        "per_field_acc_pct": per_field_acc,
        "latency": {
            "stt_mean_s": round(mean(stt_vals), 3),
            "stt_p95_s": round(_p95(stt_vals), 3),
            "extract_mean_s": round(mean(ext_vals), 3),
            "extract_p95_s": round(_p95(ext_vals), 3),
            "validate_risk_mean_s": round(mean(val_vals), 3),
            "validate_risk_p95_s": round(_p95(val_vals), 3),
            "followup_mean_s": round(mean(fup_vals), 3),
            "followup_p95_s": round(_p95(fup_vals), 3),
            "total_mean_s": round(mean(tot_vals), 3),
            "total_p95_s": round(_p95(tot_vals), 3),
        },
    }


def _ordered_conditions(rows: list[dict[str, Any]]) -> list[str]:
    present = {r["condition"] for r in rows}
    ordered = [c for c in CONDITION_ORDER if c in present]
    extras = sorted(present - set(ordered))
    return ordered + extras


def render_markdown_report(rows: list[dict[str, Any]], metadata: dict[str, Any]) -> str:
    """Render a pitch-ready Markdown evaluation report from scored rows."""
    conditions = _ordered_conditions(rows)
    by_cond = {c: [r for r in rows if r["condition"] == c] for c in conditions}

    lines: list[str] = [
        "# Asha Vaani — Evaluation Report (Milestone 8)",
        "",
        f"- **Generated (UTC):** {metadata.get('generated_at', datetime.now(timezone.utc).isoformat())}",
        f"- **LLM Provider / Model:** `{metadata.get('llm_provider', 'gemini')}` / `{metadata.get('llm_model', 'unknown')}`",
        f"- **STT / TTS Models:** `{metadata.get('stt_model', 'prisma-v3.0')}` / `{metadata.get('tts_model', 'timbre-v3.0')}`",
        f"- **Audio Provenance:** {metadata.get('audio_provenance', 'Synthetic scripted utterances (clean audio synthesized via Timbre TTS unless marked human_recording; noisy variants mixed at controlled active-speech SNR)')}",
        "",
        "## 1. Overall Accuracy & Latency by Condition",
        "",
        "| Condition | Cases | Errors | Field Acc | ID Acc | Number Acc | Risk Acc | Referral Acc | Follow-up Approp. | Mean STT (s) | Mean LLM (s) | Mean Total (s) |",
        "|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|",
    ]

    for cond in conditions:
        agg = aggregate_rows(by_cond[cond])
        lat = agg["latency"]
        lines.append(
            f"| `{cond}` | {agg['cases']} | {agg['errors']} | "
            f"{agg['field_acc_pct']}% ({agg['fields_correct']}/{agg['fields_total']}) | "
            f"{agg['id_acc_pct']}% ({agg['id_correct']}/{agg['cases']}) | "
            f"{agg['number_acc_pct']}% ({agg['numbers_correct']}/{agg['numbers_total']}) | "
            f"{agg['risk_acc_pct']}% | {agg['referral_acc_pct']}% | "
            f"{agg['followup_acc_pct']}% ({agg['followup_correct']}/{agg['cases']}) | "
            f"{lat['stt_mean_s']:.2f} | {lat['extract_mean_s']:.2f} | {lat['total_mean_s']:.2f} |"
        )

    lines.extend([
        "",
        "## 2. Per-Field Accuracy by Condition",
        "",
        "| Field | " + " | ".join(f"`{c}`" for c in conditions) + " |",
        "|---|" + "|".join("---:" for _ in conditions) + "|",
    ])
    aggs = {c: aggregate_rows(by_cond[c]) for c in conditions}
    for field in EVAL_FIELDS:
        cells = " | ".join(f"{aggs[c]['per_field_acc_pct'][field]}%" for c in conditions)
        lines.append(f"| `{field}` | {cells} |")

    lines.extend([
        "",
        "## 3. Accuracy by Language / Code-Mix Bucket",
        "",
        "| Bucket | Condition | Cases | Field Acc | ID Acc | Number Acc | Follow-up Approp. |",
        "|---|---|---:|---:|---:|---:|---:|",
    ])
    buckets = sorted({r["bucket"] for r in rows})
    for bucket in buckets:
        for cond in conditions:
            sub = [r for r in by_cond[cond] if r["bucket"] == bucket]
            if not sub:
                continue
            agg = aggregate_rows(sub)
            lines.append(
                f"| `{bucket}` | `{cond}` | {agg['cases']} | "
                f"{agg['field_acc_pct']}% | {agg['id_acc_pct']}% | "
                f"{agg['number_acc_pct']}% | {agg['followup_acc_pct']}% |"
            )

    lines.extend([
        "",
        "## 4. Per-Step Latency Breakdown (Seconds)",
        "",
        "| Condition | STT Mean / p95 | LLM Extract Mean / p95 | Validate+Risk Mean / p95 | Follow-up Mean / p95 | Total Mean / p95 |",
        "|---|---:|---:|---:|---:|---:|",
    ])
    for cond in conditions:
        lat = aggs[cond]["latency"]
        lines.append(
            f"| `{cond}` | {lat['stt_mean_s']:.2f} / {lat['stt_p95_s']:.2f} | "
            f"{lat['extract_mean_s']:.2f} / {lat['extract_p95_s']:.2f} | "
            f"{lat['validate_risk_mean_s']:.3f} / {lat['validate_risk_p95_s']:.3f} | "
            f"{lat['followup_mean_s']:.2f} / {lat['followup_p95_s']:.2f} | "
            f"{lat['total_mean_s']:.2f} / {lat['total_p95_s']:.2f} |"
        )

    lines.extend([
        "",
        "## 5. Failure Analysis & Honest Limitations",
        "",
    ])
    failures: list[str] = []
    for cond in conditions:
        for r in by_cond[cond]:
            problems: list[str] = []
            if r.get("error"):
                problems.append(f"error=`{r['error']}`")
            else:
                for fname, fres in r["field_results"].items():
                    if not fres["match"]:
                        problems.append(
                            f"`{fname}` ({fres['status']}: exp={fres['expected']!r}, got={fres['actual']!r})"
                        )
                if not r["risk_flags_exact"]:
                    problems.append(
                        f"`risk_flags` (exp={r['expected_risk_flags']}, got={r['actual_risk_flags']})"
                    )
                if not r["validation_flags_match"]:
                    problems.append(
                        f"`validation_flags` (exp={r['expected_validation_flags']}, got={r['actual_validation_flags']})"
                    )
                if not r["followup_appropriate"]:
                    problems.append(f"`followup` ({r['followup_detail']})")
            if problems:
                transcript_preview = (r.get("actual_transcript") or "").strip().replace("\n", " ")
                if len(transcript_preview) > 90:
                    transcript_preview = transcript_preview[:87] + "..."
                failures.append(
                    f"- **`{cond}` / `{r['case_id']}`** ({r['bucket']}): "
                    + "; ".join(problems)
                    + (f" — transcript: \"{transcript_preview}\"" if transcript_preview else "")
                )

    if failures:
        lines.extend(failures)
    else:
        lines.append("- No field, risk, validation, or follow-up failures observed in this run.")

    lines.append("")
    return "\n".join(lines)


def write_reports(
    rows: list[dict[str, Any]],
    metadata: dict[str, Any],
    output_dir: Path,
) -> dict[str, Path]:
    """Write eval_report.md, eval_summary.csv, eval_cases.csv, and raw_results.json."""
    output_dir.mkdir(parents=True, exist_ok=True)
    conditions = _ordered_conditions(rows)
    by_cond = {c: [r for r in rows if r["condition"] == c] for c in conditions}

    report_path = output_dir / "eval_report.md"
    report_path.write_text(render_markdown_report(rows, metadata), encoding="utf-8")

    summary_path = output_dir / "eval_summary.csv"
    with summary_path.open("w", encoding="utf-8", newline="") as f:
        writer = csv.writer(f)
        writer.writerow([
            "condition",
            "cases",
            "errors",
            "field_acc_pct",
            "fields_correct",
            "fields_total",
            "id_acc_pct",
            "number_acc_pct",
            "hallucinations",
            "risk_acc_pct",
            "referral_acc_pct",
            "validation_acc_pct",
            "followup_acc_pct",
            "stt_mean_s",
            "extract_mean_s",
            "validate_risk_mean_s",
            "followup_mean_s",
            "total_mean_s",
        ])
        for cond in conditions:
            agg = aggregate_rows(by_cond[cond])
            lat = agg["latency"]
            writer.writerow([
                cond,
                agg["cases"],
                agg["errors"],
                agg["field_acc_pct"],
                agg["fields_correct"],
                agg["fields_total"],
                agg["id_acc_pct"],
                agg["number_acc_pct"],
                agg["hallucinations"],
                agg["risk_acc_pct"],
                agg["referral_acc_pct"],
                agg["validation_acc_pct"],
                agg["followup_acc_pct"],
                lat["stt_mean_s"],
                lat["extract_mean_s"],
                lat["validate_risk_mean_s"],
                lat["followup_mean_s"],
                lat["total_mean_s"],
            ])

    cases_path = output_dir / "eval_cases.csv"
    with cases_path.open("w", encoding="utf-8", newline="") as f:
        writer = csv.writer(f)
        writer.writerow([
            "condition",
            "case_id",
            "bucket",
            "language",
            "fields_correct",
            "fields_total",
            "id_correct",
            "numbers_correct",
            "numbers_total",
            "hallucinations",
            "risk_flags_exact",
            "referral_correct",
            "validation_flags_match",
            "followup_appropriate",
            "followup_detail",
            "stt_s",
            "extract_s",
            "followup_s",
            "total_s",
            "error",
            "actual_transcript",
        ])
        for r in rows:
            writer.writerow([
                r["condition"],
                r["case_id"],
                r["bucket"],
                r["language"],
                r["fields_correct"],
                r["fields_total"],
                r["id_correct"],
                r["numbers_correct"],
                r["numbers_total"],
                r["hallucination_count"],
                r["risk_flags_exact"],
                r["referral_correct"],
                r["validation_flags_match"],
                r["followup_appropriate"],
                r["followup_detail"],
                r["stt_s"],
                r["extract_s"],
                r["followup_s"],
                r["total_s"],
                r.get("error") or "",
                r.get("actual_transcript") or "",
            ])

    raw_path = output_dir / "raw_results.json"
    raw_path.write_text(
        json.dumps({"metadata": metadata, "rows": rows}, indent=2, ensure_ascii=False),
        encoding="utf-8",
    )

    return {
        "report": report_path,
        "summary_csv": summary_path,
        "cases_csv": cases_path,
        "raw_json": raw_path,
    }
