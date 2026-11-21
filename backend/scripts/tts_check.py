"""CLI smoke check for Gnani Timbre TTS (run from backend/)."""

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
from app.services.tts_gnani import synthesize  # noqa: E402


def main() -> int:
    parser = argparse.ArgumentParser(description="Synthesize speech via Gnani Timbre.")
    parser.add_argument("text", help="Text to synthesize.")
    parser.add_argument(
        "--language",
        default="hi",
        choices=["hi", "kn", "en"],
        help="Target language (default: hi).",
    )
    parser.add_argument(
        "--out",
        type=Path,
        default=Path("out.mp3"),
        help="Output MP3 file path (default: out.mp3).",
    )
    args = parser.parse_args()

    settings = get_settings()
    try:
        audio_bytes = asyncio.run(
            synthesize(args.text, args.language, settings=settings)
        )
    except ApiError as exc:
        print(f"[{exc.code}] {exc.message}", file=sys.stderr)
        return 1

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_bytes(audio_bytes)
    print(f"Wrote {len(audio_bytes)} bytes to {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
