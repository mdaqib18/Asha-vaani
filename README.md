# Asha Vaani

Voice-first Android companion for ASHA (community health) workers to record structured newborn home-visit data in Hindi, Kannada, and code-mixed speech. See [SPEC.md](SPEC.md) for the full project specification.

## Repository Layout

```
.
├── SPEC.md
├── backend/
│   ├── app/
│   │   ├── api/            # FastAPI endpoints
│   │   ├── config/         # Visit type YAML thresholds & rules
│   │   ├── core/           # Settings and YAML config loader
│   │   ├── data/           # Synthetic beneficiary data
│   │   ├── schemas/        # Pydantic v2 models
│   │   └── services/       # Normalizer, validator, risk rules, STT/TTS stubs
│   ├── tests/
│   ├── requirements.txt
│   └── .env.example
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
- [ ] **Milestone 2:** Gnani Prisma STT integration
- [ ] **Milestone 3:** LLM extraction + validation
- [ ] **Milestone 4:** Follow-up engine + Gnani Timbre TTS
- [ ] **Milestone 5:** Flutter app (beneficiary list, record, upload, review)
- [ ] **Milestone 6:** Follow-up loop in app
- [ ] **Milestone 7:** Offline queue and sync
- [ ] **Milestone 8:** Evaluation run & noise tests
- [ ] **Milestone 9:** Polish, demo video, pitch

## Open Questions (from SPEC.md §18)

- Exact Gnani STT/TTS endpoints, auth, audio formats, languages, and credit limits (**TODO(verify)**)
- Whether the LLM is required to be a Gnani model for this hackathon (**TODO(verify)**)
- Final field list and thresholds validated by an ASHA worker/ANM (**TODO(verify)**)
- Kannada and Hindi support quality on code-mixed speech
