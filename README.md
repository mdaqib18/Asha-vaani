# Asha Vaani

Voice-first Android companion for ASHA (community health) workers to record structured newborn home-visit data in Hindi, Kannada, and code-mixed speech. See [SPEC.md](SPEC.md) for the full project specification.

## Repository Layout

```
.
├── SPEC.md
├── render.yaml             # Render deployment blueprint for backend API
├── docs/                   # Gnani API notes, UI direction, demo & pitch script
│   └── demo_and_pitch.md
├── backend/
│   ├── app/
│   │   ├── api/            # FastAPI endpoints
│   │   ├── config/         # Visit type YAML thresholds & rules
│   │   ├── core/           # Settings, API error envelope, YAML loader
│   │   ├── data/           # Synthetic beneficiary data
│   │   ├── db/             # SQLite session, audio clip, and sync persistence
│   │   ├── prompts/        # LLM system prompts (extractor.md, followup.md)
│   │   ├── schemas/        # Pydantic v2 domain & API models (newborn_visit.py, api.py)
│   │   └── services/       # Normalizer, validator, risk rules, follow-up, Gnani STT/TTS, Gemini LLM, pipeline
│   ├── scripts/            # CLI smoke checks (stt_check.py, tts_check.py, extract_check.py)
│   ├── tests/
│   ├── Procfile            # Production ASGI start command (Render/Railway)
│   ├── requirements.txt
│   └── .env.example
├── mobile/                 # Flutter Android app
│   ├── lib/
│   │   ├── l10n/           # Centralized EN / HI / KN strings
│   │   ├── models/         # Dart mirrors of backend schemas
│   │   ├── screens/        # Login, home, beneficiaries, record, review, saved visits, supervisor flagged view
│   │   ├── services/       # Dio API client, 16 kHz WAV recorder, just_audio TTS player, SQLite & sync, prefs
│   │   ├── state/          # AppState ChangeNotifier
│   │   ├── theme/          # High-contrast Clinical Teal Material 3 theme
│   │   └── widgets/        # Language toggle & server settings sheet
│   └── test/
├── eval/                   # Evaluation dataset, noise mixer, runner, and reports
│   ├── ground_truth/       # 36 scripted synthetic cases (hi, kn, code-mixed)
│   ├── results/            # Generated Markdown report, CSV tables, raw JSON
│   ├── generate_clean_audio.py
│   ├── mix_noise.py        # 16 kHz active-SNR market/traffic/crowd noise mixer
│   ├── metrics.py
│   ├── run_eval.py
│   └── README.md
└── README.md
```

## Running Backend Tests & Server (Windows)

```powershell
# Use any Python 3.11+ interpreter
<path-to-python-3.11+> -m venv backend\.venv
backend\.venv\Scripts\python -m pip install -r backend\requirements.txt
cd backend
.venv\Scripts\python -m pytest -q
```

Start the API server locally:

```powershell
cd backend
.venv\Scripts\python -m uvicorn app.main:app --reload
```

Check health: `GET http://127.0.0.1:8000/v1/health`

## Running Evaluation

```powershell
# Transcript-only (36 cases)
backend\.venv\Scripts\python.exe eval\run_eval.py --mode transcript --delay-s 2.5 --output-dir eval\results

# Generate clean audio subset + mix noise + evaluate clean vs. noisy
backend\.venv\Scripts\python.exe eval\generate_clean_audio.py --subset-only --delay-s 0.5
backend\.venv\Scripts\python.exe eval\mix_noise.py --input-dir eval\audio\clean --output-dir eval\audio\noisy --conditions market:20 traffic:10 crowd:5
backend\.venv\Scripts\python.exe eval\run_eval.py --mode audio --subset-only --conditions clean,market_20db,traffic_10db,crowd_5db --delay-s 2.5 --merge-existing --output-dir eval\results
```

## Milestone Status

- [x] **Milestone 1:** Backend skeleton, schema, config, normalizer, validator, risk rules + unit tests
- [x] **Milestone 2:** Gnani Prisma STT (+ Timbre TTS client) — live verified
- [x] **Milestone 3:** Gemini LLM extraction + validation — live verified (LLM_MODEL from .env, tested on gemini-3.5-flash)
- [x] **Milestone 4:** Follow-up engine + Gnani Timbre TTS wiring + SQLite store + FastAPI visit routes — live verified
- [x] **Milestone 5:** Flutter app (login stub, beneficiary list, push-to-talk record, upload, review & confirm)
- [x] **Milestone 6:** Follow-up loop in app (TTS question playback, auto-open mic, read-back audio)
- [x] **Milestone 7:** Offline queue and sync
- [x] **Milestone 8:** Evaluation run & noise tests
- [x] **Milestone 9:** Polish, demo video, pitch (+ ANM supervisor flagged-cases view)

## Deploy & Android APK

- **Backend (Render / Railway):** Use [render.yaml](render.yaml) or [backend/Procfile](backend/Procfile); configure `GNANI_API_KEY` and `LLM_API_KEY` as secret env vars.
- **Android Debug APK:**
  ```powershell
  cd mobile
  flutter build apk --debug
  # Output: mobile\build\app\outputs\flutter-apk\app-debug.apk
  ```
- **Demo Script & Pitch Guide:** See [docs/demo_and_pitch.md](docs/demo_and_pitch.md).

## Open Questions & Decisions (from SPEC.md §18)

- Gnani Prisma STT & Timbre TTS endpoints, auth, formats, and Hindi/Kannada support verified in [docs/gnani_api_notes.md](docs/gnani_api_notes.md) and Milestone 8 live eval
- LLM provider decided: **Gemini** (`LLM_PROVIDER=gemini`; `LLM_MODEL` set in `backend/.env`, switched to `gemini-3.5-flash-lite` in Milestone 8 after `gemini-3.5-flash` hit 20 RPD free-tier quota)
- Final field list and thresholds validated by an ASHA worker/ANM (**TODO(verify)**)
- Kannada and Hindi code-mixed quality evaluated in [eval/results/eval_report.md](eval/results/eval_report.md) (`98.1%` transcript field accuracy across 36 cases; `97.2%` on clean/`market_20db`/`traffic_10db` and `94.4%` on `crowd_5db` across the 12-case synthesized audio subset, with Kannada negation drops under 5 dB babble)
