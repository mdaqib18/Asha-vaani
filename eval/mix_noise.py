"""Deterministic 16 kHz mono PCM WAV noise generator and SNR mixer for Asha Vaani eval."""

from __future__ import annotations

import argparse
from array import array
from collections.abc import Sequence
import json
import math
from pathlib import Path
import random
import subprocess
import sys
from typing import Any, Literal
import wave

NoiseType = Literal["market", "traffic", "crowd"]
SUPPORTED_NOISE_TYPES: tuple[NoiseType, ...] = ("market", "traffic", "crowd")


def read_wav_pcm16(path: Path) -> tuple[list[int], int]:
    """Read a mono 16-bit PCM WAV file into integer samples and sample rate."""
    with wave.open(str(path), "rb") as wf:
        channels = wf.getnchannels()
        sampwidth = wf.getsampwidth()
        framerate = wf.getframerate()
        nframes = wf.getnframes()
        if channels != 1 or sampwidth != 2:
            raise ValueError(
                f"Expected mono 16-bit PCM WAV in {path}, got channels={channels}, sampwidth={sampwidth}"
            )
        raw = wf.readframes(nframes)

    pcm = array("h")
    pcm.frombytes(raw)
    if sys.byteorder != "little":
        pcm.byteswap()
    return list(pcm), framerate


def write_wav_pcm16(
    path: Path,
    samples: Sequence[int] | array,
    sample_rate: int = 16000,
) -> None:
    """Write mono 16-bit PCM samples to a WAV file."""
    path.parent.mkdir(parents=True, exist_ok=True)
    clamped = array("h", (max(-32768, min(32767, int(s))) for s in samples))
    if sys.byteorder != "little":
        clamped.byteswap()
    with wave.open(str(path), "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(sample_rate)
        wf.writeframes(clamped.tobytes())


def convert_to_wav_16k_mono(src: Path, dst: Path) -> Path:
    """Convert any audio file into 16 kHz mono 16-bit PCM WAV using ffmpeg."""
    dst.parent.mkdir(parents=True, exist_ok=True)
    cmd = [
        "ffmpeg",
        "-y",
        "-i",
        str(src),
        "-ac",
        "1",
        "-ar",
        "16000",
        "-sample_fmt",
        "s16",
        str(dst),
    ]
    proc = subprocess.run(
        cmd,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    if proc.returncode != 0 or not dst.is_file():
        raise RuntimeError(
            f"ffmpeg conversion failed for {src} -> {dst} (code {proc.returncode}): {proc.stderr[-300:]}"
        )
    return dst


def compute_active_rms(samples: Sequence[int | float]) -> float:
    """Compute RMS over active samples (>= 1% of peak amplitude, fallback full clip)."""
    if not samples:
        return 0.0
    peak = max(abs(float(s)) for s in samples)
    if peak == 0.0:
        return 0.0
    thresh = peak * 0.01
    active = [float(s) for s in samples if abs(float(s)) >= thresh]
    if not active:
        active = [float(s) for s in samples]
    return math.sqrt(sum(v * v for v in active) / len(active))


def _generate_traffic_noise(num_samples: int, sample_rate: int, rng: random.Random) -> list[float]:
    y = 0.0
    phase = rng.uniform(0.0, 2.0 * math.pi)
    out: list[float] = []
    # 2 brief distant horn bursts spaced roughly every ~4 seconds.
    horn_period = int(4.2 * sample_rate)
    horn_len = int(0.35 * sample_rate)
    horn_offset = rng.randint(int(0.5 * sample_rate), max(int(0.6 * sample_rate), horn_period - 1))

    for i in range(num_samples):
        x = rng.gauss(0.0, 1.0)
        y = 0.94 * y + 0.06 * x
        mod = 0.65 + 0.35 * math.sin(2.0 * math.pi * 0.35 * i / sample_rate + phase)
        val = y * mod * 3.0
        pos = (i + horn_offset) % max(1, horn_period)
        if pos < horn_len:
            env = math.sin(math.pi * pos / horn_len)
            t = i / sample_rate
            horn = 0.55 * math.sin(2.0 * math.pi * 380.0 * t) + 0.45 * math.sin(2.0 * math.pi * 475.0 * t)
            val += 0.18 * env * horn
        out.append(val)
    return out


def _generate_crowd_noise(num_samples: int, sample_rate: int, rng: random.Random) -> list[float]:
    num_speakers = 5
    mod_freqs = [3.2, 3.9, 4.7, 5.4, 6.1]
    phases = [rng.uniform(0.0, 2.0 * math.pi) for _ in range(num_speakers)]
    lp_fast = [0.0] * num_speakers
    lp_slow = [0.0] * num_speakers
    out = [0.0] * num_samples

    # 1-pole cutoff coefficients at 16 kHz (~1.8 kHz fast, ~250 Hz slow).
    a_fast = 0.50
    a_slow = 0.91
    for i in range(num_samples):
        t = i / sample_rate
        total = 0.0
        for s_idx in range(num_speakers):
            x = rng.gauss(0.0, 1.0)
            lp_fast[s_idx] = a_fast * lp_fast[s_idx] + (1.0 - a_fast) * x
            lp_slow[s_idx] = a_slow * lp_slow[s_idx] + (1.0 - a_slow) * x
            band = lp_fast[s_idx] - lp_slow[s_idx]
            env = 0.5 + 0.5 * math.sin(2.0 * math.pi * mod_freqs[s_idx] * t + phases[s_idx])
            total += band * env
        out[i] = total
    return out


def _generate_market_noise(num_samples: int, sample_rate: int, rng: random.Random) -> list[float]:
    crowd = _generate_crowd_noise(num_samples, sample_rate, rng)
    crowd_rms = compute_active_rms(crowd) or 1.0
    # Add short metallic/stall clatter bursts on top of multi-speaker babble.
    burst_period = max(1, int(1.4 * sample_rate))
    burst_decay = 1.0 / max(1.0, 0.08 * sample_rate)
    offset = rng.randint(0, max(0, burst_period - 1))
    out: list[float] = []
    for i, val in enumerate(crowd):
        pos = (i + offset) % burst_period
        burst = 0.0
        if pos < int(0.25 * sample_rate):
            env = math.exp(-pos * burst_decay)
            burst = rng.gauss(0.0, 1.0) * env * crowd_rms * 0.9
        out.append(0.75 * val + 0.25 * burst)
    return out


def generate_noise(
    noise_type: NoiseType,
    num_samples: int,
    sample_rate: int = 16000,
    seed: int = 0,
) -> list[float]:
    """Generate deterministic ambient noise samples of requested type and length."""
    if num_samples <= 0:
        return []
    if noise_type not in SUPPORTED_NOISE_TYPES:
        raise ValueError(f"Unsupported noise_type '{noise_type}'. Choose from {SUPPORTED_NOISE_TYPES}")
    rng = random.Random(seed)
    if noise_type == "traffic":
        return _generate_traffic_noise(num_samples, sample_rate, rng)
    if noise_type == "crowd":
        return _generate_crowd_noise(num_samples, sample_rate, rng)
    return _generate_market_noise(num_samples, sample_rate, rng)


def _load_or_generate_noise(
    noise_type: NoiseType,
    num_samples: int,
    sample_rate: int,
    noise_dir: Path | None,
    seed: int,
) -> tuple[list[float], bool]:
    if noise_dir is not None:
        candidate = noise_dir / f"{noise_type}.wav"
        if candidate.is_file():
            samples, sr = read_wav_pcm16(candidate)
            if sr == sample_rate and samples:
                tiled = [float(samples[i % len(samples)]) for i in range(num_samples)]
                return tiled, True
    return generate_noise(noise_type, num_samples, sample_rate=sample_rate, seed=seed), False


def mix_at_snr(
    speech: Sequence[int],
    noise: Sequence[float],
    snr_db: float,
) -> list[int]:
    """Mix speech and noise so active speech RMS exceeds noise RMS by snr_db."""
    if not speech:
        return []
    if len(noise) < len(speech):
        raise ValueError(f"Noise length ({len(noise)}) shorter than speech ({len(speech)})")

    noise_slice = [float(n) for n in noise[: len(speech)]]
    speech_rms = compute_active_rms(speech)
    noise_rms = math.sqrt(sum(n * n for n in noise_slice) / len(noise_slice))

    if speech_rms == 0.0 or noise_rms == 0.0:
        return [max(-32768, min(32767, int(s))) for s in speech]

    target_noise_rms = speech_rms / (10.0 ** (snr_db / 20.0))
    scale = target_noise_rms / noise_rms

    mixed = [float(s) + n * scale for s, n in zip(speech, noise_slice)]
    max_amp = max((abs(v) for v in mixed), default=0.0)
    if max_amp > 32767.0:
        headroom = 32767.0 / max_amp
        mixed = [v * headroom for v in mixed]

    return [max(-32768, min(32767, int(round(v)))) for v in mixed]


def format_condition_name(noise_type: str, snr_db: float) -> str:
    """Format canonical noisy condition folder name, e.g. market_20db."""
    snr_str = str(int(snr_db)) if float(snr_db).is_integer() else str(snr_db).replace(".", "p")
    return f"{noise_type}_{snr_str}db"


def parse_condition(spec: str) -> tuple[NoiseType, float]:
    """Parse condition strings like 'market:20' or 'market_20db' into (noise_type, snr_db)."""
    raw = spec.strip().lower()
    if ":" in raw:
        ntype, snr_raw = raw.split(":", 1)
    elif "_" in raw and raw.endswith("db"):
        ntype, snr_part = raw.rsplit("_", 1)
        snr_raw = snr_part[:-2].replace("p", ".")
    else:
        raise ValueError(f"Invalid condition spec '{spec}'. Expected '<noise>:<snr_db>' or '<noise>_<snr>db'.")

    if ntype not in SUPPORTED_NOISE_TYPES:
        raise ValueError(f"Unsupported noise type '{ntype}' in '{spec}'.")
    return ntype, float(snr_raw)  # type: ignore[return-value]


def mix_file(
    clean_wav: Path,
    out_wav: Path,
    noise_type: NoiseType,
    snr_db: float,
    *,
    noise_dir: Path | None = None,
    seed: int = 0,
) -> dict[str, Any]:
    """Mix one clean 16 kHz mono WAV file with noise at target SNR and write out_wav."""
    speech, sr = read_wav_pcm16(clean_wav)
    noise, used_real = _load_or_generate_noise(
        noise_type,
        len(speech),
        sample_rate=sr,
        noise_dir=noise_dir,
        seed=seed,
    )
    mixed = mix_at_snr(speech, noise, snr_db)
    write_wav_pcm16(out_wav, mixed, sample_rate=sr)
    return {
        "input": str(clean_wav),
        "output": str(out_wav),
        "noise_type": noise_type,
        "snr_db": snr_db,
        "sample_rate": sr,
        "num_samples": len(mixed),
        "used_real_noise": used_real,
    }


def main(argv: list[str] | None = None) -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")

    parser = argparse.ArgumentParser(description="Mix clean 16 kHz WAV files with ambient noise at target SNRs.")
    parser.add_argument("--input-dir", type=Path, default=Path("eval/audio/clean"))
    parser.add_argument("--output-dir", type=Path, default=Path("eval/audio/noisy"))
    parser.add_argument("--noise-dir", type=Path, default=Path("eval/audio/noise"))
    parser.add_argument(
        "--conditions",
        nargs="+",
        default=["market:20", "traffic:10", "crowd:5"],
        help="List of <noise_type>:<snr_db> pairs (e.g. market:20 traffic:10 crowd:5).",
    )
    parser.add_argument("--seed", type=int, default=42)
    args = parser.parse_args(argv)

    if not args.input_dir.is_dir():
        print(f"Error: input directory not found: {args.input_dir}", file=sys.stderr)
        return 1

    wav_files = sorted(args.input_dir.glob("*.wav"))
    if not wav_files:
        print(f"Error: no .wav files found in {args.input_dir}", file=sys.stderr)
        return 1

    parsed_conditions = [parse_condition(spec) for spec in args.conditions]
    manifest: list[dict[str, Any]] = []

    for cond_idx, (noise_type, snr_db) in enumerate(parsed_conditions):
        cond_name = format_condition_name(noise_type, snr_db)
        cond_dir = args.output_dir / cond_name
        for file_idx, wav_path in enumerate(wav_files):
            item_seed = args.seed + cond_idx * 1000 + file_idx
            info = mix_file(
                wav_path,
                cond_dir / wav_path.name,
                noise_type,
                snr_db,
                noise_dir=args.noise_dir if args.noise_dir.is_dir() else None,
                seed=item_seed,
            )
            info["condition"] = cond_name
            manifest.append(info)
        print(f"Mixed {len(wav_files)} files for {cond_name} -> {cond_dir}")

    args.output_dir.mkdir(parents=True, exist_ok=True)
    (args.output_dir / "noise_manifest.json").write_text(
        json.dumps(manifest, indent=2),
        encoding="utf-8",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
