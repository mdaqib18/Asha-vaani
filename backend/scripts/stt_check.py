"""CLI smoke check for Gnani Prisma STT (run from backend/)."""

from __future__ import annotations

import argparse
import asyncio
import sys
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parent.parent
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

from app.core.errors import ApiError  # noqa: E402
from app.core.settings import get_settings  # noqa: E402
from app.services.stt_gnani import transcribe  # noqa: E402


def main() -> int:
    parser = argparse.ArgumentParser(description="Transcribe an audio file via Gnani Prisma.")
    parser.add_argument("audio_path", type=Path, help="Path to audio clip (<= 30s).")
    parser.add_argument(
        "--language",
        default="hi",
        choices=["hi", "kn", "en"],
        help="Primary speech language (default: hi).",
    )
    args = parser.parse_args()

    if not args.audio_path.is_file():
        print(f"Error: file not found: {args.audio_path}", file=sys.stderr)
        return 1

    audio_bytes = args.audio_path.read_bytes()
    settings = get_settings()
    try:
        result = asyncio.run(
            transcribe(audio_bytes, args.audio_path.name, args.language, settings=settings)
        )
    except ApiError as exc:
        print(f"[{exc.code}] {exc.message}", file=sys.stderr)
        return 1

    print(f"Transcript: {result.transcript}")
    print(f"Detected language: {result.detected_language}")
    print(f"Model: {result.model}")
    print(f"Latency (s): {result.latency_s}")
    if result.truncated:
        print("Warning: transcript was truncated.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
