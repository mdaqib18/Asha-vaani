"""CLI smoke check for Milestone 3 pipeline (run from backend/)."""

from __future__ import annotations

import argparse
import asyncio
import json
import sys
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parent.parent
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

from app.core.errors import ApiError  # noqa: E402
from app.core.settings import get_settings  # noqa: E402
from app.data.beneficiaries import get_assigned_ids  # noqa: E402
from app.services.pipeline import process_audio, process_transcript  # noqa: E402


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Run STT (optional) + Gemini extraction + validation + risk pipeline."
    )
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--text", help="Transcript text to extract.")
    source.add_argument("--audio", type=Path, help="Audio file path (<= 30s) to transcribe and extract.")
    parser.add_argument(
        "--language",
        default="hi",
        choices=["hi", "kn", "en"],
        help="Primary speech language (default: hi).",
    )
    parser.add_argument(
        "--asha-id",
        default="asha_001",
        help="ASHA worker ID for beneficiary validation (default: asha_001).",
    )
    args = parser.parse_args()

    settings = get_settings()
    assigned_ids = get_assigned_ids(args.asha_id)

    try:
        if args.text is not None:
            result = asyncio.run(
                process_transcript(
                    args.text,
                    args.language,
                    assigned_ids=assigned_ids,
                    settings=settings,
                )
            )
        else:
            if not args.audio.is_file():
                print(f"Error: file not found: {args.audio}", file=sys.stderr)
                return 1
            audio_bytes = args.audio.read_bytes()
            result = asyncio.run(
                process_audio(
                    audio_bytes,
                    args.audio.name,
                    args.language,
                    assigned_ids=assigned_ids,
                    settings=settings,
                )
            )
    except ApiError as exc:
        print(f"[{exc.code}] {exc.message}", file=sys.stderr)
        return 1

    print(f"Transcript: {result.transcript}")
    print("Record:")
    print(json.dumps(result.record.model_dump(mode="json", exclude_none=True), indent=2, ensure_ascii=False))
    print(f"Flags: {[f.model_dump() for f in result.flags]}")
    print(f"Missing required: {result.missing_required}")
    print(f"Ambiguities: {[a.model_dump() for a in result.ambiguities]}")
    print(f"Risk flags: {result.record.risk_flags}")
    print(f"Referral suggested: {result.record.referral_suggested}")
    print(f"Latencies (s): stt={result.stt_latency_s}, llm={result.llm_latency_s}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
