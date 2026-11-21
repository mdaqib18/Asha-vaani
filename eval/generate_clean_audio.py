"""Synthesize clean 16 kHz mono WAV evaluation clips via Gnani Timbre TTS (never overwrites existing human clips)."""

from __future__ import annotations

import argparse
import asyncio
import json
from pathlib import Path
import sys
import tempfile

import httpx

REPO_ROOT = Path(__file__).resolve().parent.parent
BACKEND_DIR = REPO_ROOT / "backend"
for path in (str(REPO_ROOT), str(BACKEND_DIR)):
    if path not in sys.path:
        sys.path.insert(0, path)

from app.core.errors import ApiError  # noqa: E402
from app.core.settings import get_settings  # noqa: E402
from app.services.tts_gnani import synthesize  # noqa: E402
from eval.metrics import load_cases  # noqa: E402
from eval.mix_noise import convert_to_wav_16k_mono  # noqa: E402


async def generate_clean_clips(
    cases: list[dict],
    output_dir: Path,
    *,
    overwrite: bool = False,
    delay_s: float = 0.4,
) -> dict[str, str]:
    """Synthesize missing clean WAV clips via Timbre TTS and update source_manifest.json."""
    output_dir.mkdir(parents=True, exist_ok=True)
    manifest_path = output_dir / "source_manifest.json"
    existing_manifest: dict[str, str] = {}
    if manifest_path.is_file():
        loaded = json.loads(manifest_path.read_text(encoding="utf-8"))
        if isinstance(loaded, dict):
            existing_manifest = {str(k): str(v) for k, v in loaded.items()}

    settings = get_settings()
    manifest = dict(existing_manifest)

    async with httpx.AsyncClient(timeout=settings.GNANI_TIMEOUT_S) as client:
        for idx, case in enumerate(cases):
            case_id = case["id"]
            wav_path = output_dir / f"{case_id}.wav"
            if wav_path.is_file() and not overwrite:
                manifest.setdefault(case_id, "human_recording")
                print(f"[{idx + 1}/{len(cases)}] Skip existing {wav_path.name} ({manifest[case_id]})")
                continue

            print(f"[{idx + 1}/{len(cases)}] Synthesizing {case_id} ({case['language']})...")
            try:
                mp3_bytes = await synthesize(
                    case["transcript"],
                    case["language"],
                    settings=settings,
                    client=client,
                )
            except ApiError as exc:
                print(
                    f"  FAILED {case_id}: {exc.code} - {exc.message}",
                    file=sys.stderr,
                )
                continue

            with tempfile.NamedTemporaryFile(suffix=".mp3", delete=False) as tmp:
                tmp.write(mp3_bytes)
                tmp_path = Path(tmp.name)
            try:
                convert_to_wav_16k_mono(tmp_path, wav_path)
            finally:
                tmp_path.unlink(missing_ok=True)

            manifest[case_id] = "synthesized_tts"
            if delay_s > 0 and idx + 1 < len(cases):
                await asyncio.sleep(delay_s)

    manifest_path.write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False),
        encoding="utf-8",
    )
    return manifest


def main(argv: list[str] | None = None) -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")

    parser = argparse.ArgumentParser(description="Generate clean 16 kHz mono WAV evaluation clips via Timbre TTS.")
    parser.add_argument("--ground-truth-dir", type=Path, default=Path("eval/ground_truth"))
    parser.add_argument("--output-dir", type=Path, default=Path("eval/audio/clean"))
    parser.add_argument("--subset-only", action="store_true", help="Generate only for audio_subset cases (default).")
    parser.add_argument("--all", action="store_true", help="Generate for all cases instead of audio_subset only.")
    parser.add_argument("--overwrite", action="store_true", help="Overwrite existing clean WAV files.")
    parser.add_argument("--delay-s", type=float, default=0.4)
    args = parser.parse_args(argv)

    cases = load_cases(args.ground_truth_dir, subset_only=not args.all)
    if not cases:
        print("No matching cases found.", file=sys.stderr)
        return 1

    asyncio.run(
        generate_clean_clips(
            cases,
            args.output_dir,
            overwrite=args.overwrite,
            delay_s=args.delay_s,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
