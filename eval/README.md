# Asha Vaani Evaluation (`eval/`)

Reproducible evaluation suite measuring field-level accuracy, ID/number accuracy, risk & validation accuracy, follow-up appropriateness, and per-step latency across clean transcripts and noisy 16 kHz audio (`SPEC.md §12`).

## Directory Structure

- `ground_truth/` — 36 synthetic scripted newborn home-visit cases (`hi_cases.json`, `kn_cases.json`, `codemix_cases.json`), 12 with `audio_subset: true` (`4 hi`, `4 kn`, `4 code-mixed`).
- `audio/` *(git-ignored)* — clean 16 kHz mono PCM WAV clips (`clean/`) and noisy SNR-mixed variants (`noisy/market_20db`, `noisy/traffic_10db`, `noisy/crowd_5db`).
- `mix_noise.py` — deterministic 16 kHz PCM WAV noise generator (`market`, `traffic`, `crowd`) and active-speech SNR mixer (also supports real ambient `.wav` clips placed under `eval/audio/noise/{market,traffic,crowd}.wav`).
- `generate_clean_audio.py` — synthesizes clean 16 kHz mono WAVs via Gnani Timbre TTS for any missing clips while preserving existing teammate human recordings (`source_manifest.json` records provenance per clip).
- `metrics.py` — field-level comparison (tolerances, hallucination checks, risk & validation flags, follow-up appropriateness) plus Markdown/CSV/JSON report writers.
- `run_eval.py` — end-to-end evaluator across `transcript`, `clean`, and noisy conditions.
- `results/` — generated `eval_report.md`, `eval_summary.csv`, `eval_cases.csv`, and `raw_results.json`.

## Placing Human Recordings (Recommended for Pitch / Demo)

Place consenting teammate 16 kHz mono 16-bit PCM WAV files at `eval/audio/clean/<case_id>.wav` (e.g. `hi_01.wav`, `mix_02.wav`). `generate_clean_audio.py` will never overwrite existing files unless `--overwrite` is passed, and records provenance honestly in `eval/audio/clean/source_manifest.json`.

## Running

```powershell
# 1. Transcript-only evaluation across all 36 cases
backend\.venv\Scripts\python.exe eval\run_eval.py --mode transcript --delay-s 0.4 --output-dir eval\results

# 2. Generate clean audio for the 12-case balanced subset (skips existing WAVs)
backend\.venv\Scripts\python.exe eval\generate_clean_audio.py --subset-only --delay-s 0.4

# 3. Mix market (20 dB), traffic (10 dB), and crowd (5 dB) noise locally
backend\.venv\Scripts\python.exe eval\mix_noise.py --input-dir eval\audio\clean --output-dir eval\audio\noisy --conditions market:20 traffic:10 crowd:5

# 4. Run clean + noisy audio eval and merge with transcript results
backend\.venv\Scripts\python.exe eval\run_eval.py --mode audio --subset-only --conditions clean,market_20db,traffic_10db,crowd_5db --delay-s 0.4 --merge-existing --output-dir eval\results
```
