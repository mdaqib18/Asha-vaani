# Asha Vaani

Voice-first Android companion for ASHA (community health) workers to record structured newborn home-visit data in Hindi, Kannada, and code-mixed speech. See [SPEC.md](SPEC.md) for the full project specification.

## Repository Layout

```
.
├── SPEC.md
├── docs/                   # Gnani API notes and UI direction
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
│   ├── requirements.txt
│   └── .env.example
├── mobile/                 # Flutter Android app
│   ├── lib/
│   │   ├── l10n/           # Centralized EN / HI / KN strings
│   │   ├── models/         # Dart mirrors of backend schemas
│   │   ├── screens/        # Login, home, beneficiaries, record, review, saved visits
│   │   ├── services/       # Dio API client, 16 kHz WAV recorder, just_audio TTS player, SQLite & sync, prefs
│   │   ├── state/          # AppState ChangeNotifier
│   │   ├── theme/          # High-contrast Clinical Teal Material 3 theme
│   │   └── widgets/        # Language toggle & server settings sheet
│   └── test/
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

## Milestone Status

- [x] **Milestone 1:** Backend skeleton, schema, config, normalizer, validator, risk rules + unit tests
- [x] **Milestone 2:** Gnani Prisma STT (+ Timbre TTS client) — live verified
- [x] **Milestone 3:** Gemini LLM extraction + validation — live verified (LLM_MODEL from .env, tested on gemini-3.5-flash)
- [x] **Milestone 4:** Follow-up engine + Gnani Timbre TTS wiring + SQLite store + FastAPI visit routes — live verified
- [x] **Milestone 5:** Flutter app (login stub, beneficiary list, push-to-talk record, upload, review & confirm)
- [x] **Milestone 6:** Follow-up loop in app (TTS question playback, auto-open mic, read-back audio)
- [x] **Milestone 7:** Offline queue and sync
- [ ] **Milestone 8:** Evaluation run & noise tests
- [ ] **Milestone 9:** Polish, demo video, pitch

## Open Questions & Decisions (from SPEC.md §18)

- Gnani Prisma STT & Timbre TTS endpoints, auth, formats, and Hindi/Kannada support verified in [docs/gnani_api_notes.md](docs/gnani_api_notes.md); live credit limits & code-mixed STT accuracy pending API key test
- LLM provider decided: **Gemini** (`LLM_PROVIDER=gemini` for Milestone 3)
- Final field list and thresholds validated by an ASHA worker/ANM (**TODO(verify)**)
- Kannada and Hindi support quality on code-mixed speech (evaluate once live key is set)
