# Asha Vaani: Project Spec for Antigravity

> Put this file at the repo root. Reference it in every agent prompt ("follow SPEC.md"). If something here conflicts with a prompt, ask before deviating. Items marked **TODO(verify)** must be checked against real docs or a real ASHA worker before being treated as fact.

---

## 1. One-line summary

A voice-first Android app for ASHA (community health) workers: the worker speaks a home-visit record in her own language (code-mixed is fine), the app turns it into a structured, validated record, and a background LLM asks a short follow-up question only if something important is missing or unclear.

## 2. Problem

ASHA workers visit homes for checkups and data collection, then must maintain paper registers and reports. Writing is slow, error-prone, and often done later from memory. Speaking is faster and more natural than typing or writing, especially in the field.

## 3. Users

- **Primary:** ASHA worker. Low-to-moderate digital literacy, mid/low-end Android phone, noisy environments, intermittent connectivity.
- **Secondary (stretch only):** ANM / supervisor who reviews flagged cases.

## 4. Scope

### In scope (MVP)
1. One visit type: **Newborn home visit** (see schema in section 7).
2. Two languages: **Hindi** and **Kannada** (**TODO(verify)**: confirm both are supported by Gnani Prisma and Timbre; swap if not). Code-mixing with English words and numbers must work.
3. Push-to-talk recording, upload, transcript, structured record, confirmation screen.
4. Follow-up loop: deterministic missing-field check plus LLM follow-up for ambiguity, spoken aloud with TTS. Maximum 2 follow-ups per visit.
5. Read-back confirmation of key fields (ID, weight, temperature).
6. Offline-first: save audio and draft locally, sync when online.
7. Rule-based risk flags (not LLM diagnosis).
8. Evaluation script with a scripted test set, clean vs. noisy audio.

### Out of scope
- iOS, web UI, multi-user auth beyond a simple login stub.
- Real beneficiary data or real government system integration.
- Medical diagnosis or treatment advice by the LLM.
- Full conflict resolution for sync (last write wins is fine).
- Supervisor dashboard (stretch only, after everything works).

### Positioning (for pitch)
Asha Vaani is a **voice capture layer** that produces records in the formats ASHA workers already use. It does not replace existing government reporting systems.

## 5. Architecture

```
[Flutter Android app]
   | record audio (mono, 16 kHz), local SQLite, offline queue
   v
[FastAPI backend]
   1. STT: Gnani Prisma  -> transcript
   2. Normalizer: spoken numbers/units -> clean values
   3. Extractor: LLM (JSON mode) -> partial record per schema
   4. Validator: ranges + required fields + risk rules (deterministic)
   5. Follow-up engine: rules first, LLM only for ambiguity
   6. TTS: Gnani Timbre -> audio for follow-up question
   7. Store: SQLite
   v
[App shows structured record -> worker confirms/edits -> saved]
```

**Principle:** all AI and business logic lives on the backend. The app only records, uploads, displays, plays audio, and stores locally. This lets us fix logic without rebuilding the APK.

## 6. Tech stack (final)

| Layer | Choice |
|---|---|
| IDE | Google Antigravity with official Dart and Flutter tools |
| Mobile | Flutter (Dart), Android only |
| Audio record | `record` package, mono, 16 kHz, push-to-talk |
| Audio play | `just_audio` or `audioplayers` |
| State mgmt | Riverpod (or `setState` if simpler) |
| Local DB | `sqflite` or `drift` |
| HTTP | `dio` |
| Backend | Python 3.11+, FastAPI, Pydantic v2, Uvicorn |
| STT | Gnani Prisma (**TODO(verify)**: endpoint, auth, audio format from docs.gnani.ai) |
| TTS | Gnani Timbre, beta (**TODO(verify)**: same) |
| LLM | Hosted LLM with structured JSON output. Provider is configurable via env var. **TODO(verify)**: hackathon rules on LLM choice. |
| Server DB | SQLite via SQLAlchemy (Supabase optional) |
| Deploy | Render or Railway; debug APK on a real phone |

Environment variables (backend `.env`, never commit):
```
GNANI_API_KEY=
GNANI_STT_URL=        # fill from docs
GNANI_TTS_URL=        # fill from docs
LLM_PROVIDER=
LLM_API_KEY=
LLM_MODEL=
DATABASE_URL=sqlite:///./ashavaani.db
MAX_FOLLOWUPS=2
```

## 7. Data schema: Newborn home visit

Source of truth: `backend/app/schemas/newborn_visit.py` (Pydantic) mirrored by a Dart model. Field list and thresholds below are **TODO(verify)** with an ASHA worker/ANM or the official home-based newborn care (HBNC) guidance before the demo. Keep thresholds in a config file, not hardcoded in logic.

| Field | Type | Required | Validation / notes |
|---|---|---|---|
| `beneficiary_id` | string | yes | Prefer selection from the assigned list. If spoken, must match an assigned ID, otherwise flag. |
| `visit_date` | date | auto | Set by app. |
| `baby_weight_kg` | float | yes | Plausible range 0.5 to 6.0. Flag low birth weight if < 2.5. |
| `temperature_c` | float | yes | Plausible range 34.0 to 41.0. Flag if >= 37.5 or < 35.5. Accept Fahrenheit if unit spoken and convert. |
| `breastfeeding` | enum | yes | `exclusive`, `partial`, `not_feeding`, `unknown` |
| `cord_status` | enum | yes | `clean_dry`, `red_swollen`, `pus_discharge`, `unknown` |
| `jaundice` | bool | yes | |
| `breathing_rate_per_min` | int | no | Plausible 20 to 100. Flag if > 60. |
| `limb_abnormality` | object | yes (present true/false) | `{present: bool, location: enum[left_arm,right_arm,left_leg,right_leg,both_arms,both_legs,unspecified], description: string?}` |
| `danger_signs` | list[enum] | no | e.g. `not_feeding`, `convulsions`, `lethargy`, `fast_breathing`, `fever`, `hypothermia`, `pus_umbilicus` |
| `mother_notes` | string | no | Short free text. |
| `notes` | string | no | Anything else the worker said. |
| `risk_flags` | list[string] | computed | Produced ONLY by deterministic rules, never by the LLM. |
| `referral_suggested` | bool | computed | True if any high-risk flag fires. Wording in UI: "Suggest consulting ANM/doctor", not a diagnosis. |

Each extracted field also carries: `value`, `confidence` (0 to 1 or `low/med/high`), `source` (`speech` | `typed` | `selected`), and `needs_confirmation` (bool).

Example target extraction for the utterance *"Beneficiary 1042, weight 2.5 kg hai, aur limb problem hai"*:
```json
{
  "beneficiary_id": {"value": "1042", "confidence": 0.7, "needs_confirmation": true},
  "baby_weight_kg": {"value": 2.5, "confidence": 0.9, "needs_confirmation": true},
  "limb_abnormality": {"value": {"present": true, "location": "unspecified"}, "confidence": 0.8, "needs_confirmation": false}
}
```
Expected follow-up: one combined question for missing required fields (temperature, breastfeeding, cord, jaundice), then one LLM follow-up for which limb is affected.

## 8. Processing pipeline details

### 8.1 Normalization (deterministic, before and after LLM)
Handle spoken forms and mixed scripts:
- Number words in Hindi/Kannada/English ("dhai", "dhaai kilo", "two point five", "ippattu" etc.) to numbers.
- Units: kg, gram(s), g, "sau gram" to a canonical kg float. Celsius/Fahrenheit.
- Digit sequences for IDs ("ek zero chaar do" to `1042`). Strip spaces and fillers.
- Keep a unit-tested `normalize.py` with a table-driven test suite. This is cheap and high value.

### 8.2 Extraction (LLM)
- Input: transcript, language, visit type, schema as JSON Schema, list of fields already filled.
- Output: JSON only, validated by Pydantic. On parse failure, retry once, then fall back to "ask the worker to repeat".
- Rules in the system prompt:
  - Extract only what was actually said. Never guess or fill defaults.
  - If a value is ambiguous, set it null and add it to `ambiguities` with a short reason.
  - Do not diagnose or give medical advice.
  - Preserve numbers exactly as spoken (normalization happens in code).

### 8.3 Validation (deterministic)
- Pydantic types and enums.
- Plausible-range checks (see schema). Out-of-range values are NOT silently fixed. They become flagged fields that must be confirmed (e.g. 25 kg likely means 2.5).
- Required-field check per visit type from `config/visit_types/newborn.yaml`.
- Risk rules produce `risk_flags` and `referral_suggested`.

### 8.4 Follow-up engine
Order of operations:
1. **Missing required fields** (deterministic). Bundle into ONE natural question, e.g. "Temperature, breastfeeding, cord and jaundice details are missing. Please tell me." Text templates per language.
2. **Ambiguity follow-up** (LLM). Only if the extractor listed ambiguities or a clinically relevant statement is vague (e.g. limb problem with no location). The LLM writes one short question in the worker's language.
3. Hard cap: `MAX_FOLLOWUPS` (default 2) per visit. After the cap, go to confirmation with remaining gaps marked "not recorded".
4. Never ask about a field already filled.
5. Question text is sent to TTS. The app plays it and automatically opens the mic for the answer.

### 8.5 Confirmation
- Show the full record as editable cards. Highlight `needs_confirmation` and flagged fields.
- Read back key fields by TTS: ID, weight, temperature. Worker says/taps yes or fixes by voice or typing.
- Nothing is saved as final until the worker confirms.

## 9. Noisy audio strategy

1. **Capture:** mono, 16 kHz, push-to-talk, hold phone close. Use Android's voice-oriented audio source where the plugin supports it (**TODO(verify)**: whether device noise suppression/echo cancellation can be enabled via the `record` package config).
2. **Don't over-clean:** send raw audio to Prisma first (trained on telephone-style audio). Add a light denoiser (`noisereduce` or RNNoise) on the backend ONLY if the eval shows it helps.
3. **Post-ASR safety nets:** normalization, range checks, confidence flags, assigned-ID matching.
4. **Confirm risky fields** by read-back. Fallback to typed input or ID picker.
5. **Evaluate:** see section 12.

## 10. API contract (backend)

Base path `/v1`. JSON unless noted. Align exact STT/TTS calls with Gnani docs.

### `GET /v1/health`
Returns `{"status":"ok"}`.

### `GET /v1/beneficiaries?asha_id={id}`
Returns assigned beneficiaries (synthetic data). `[{ "id": "1042", "label": "Baby of Sunita (synthetic)" }]`

### `POST /v1/visits/audio` (multipart/form-data)
Fields: `audio` (file), `language` (`hi`|`kn`|`en`), `visit_type` (`newborn_home_visit`), `session_id` (optional, omit to start a new visit), `beneficiary_id` (optional, if selected from the list).

Response:
```json
{
  "session_id": "uuid",
  "transcript": "string",
  "record": { "...fields as in section 7, each with value/confidence/needs_confirmation..." },
  "flags": [{"field": "baby_weight_kg", "reason": "out_of_range"}],
  "risk_flags": ["low_birth_weight"],
  "status": "needs_followup",
  "followup": {
    "question_text": "string",
    "question_audio_url": "string",
    "target_fields": ["limb_abnormality.location"],
    "followup_count": 1
  }
}
```
`status` is one of `needs_followup`, `ready_to_confirm`, `error_retry`. `followup` is null unless `status = needs_followup`.

### `POST /v1/visits/{session_id}/answer` (multipart/form-data)
Fields: `audio`, `language`. Same response shape as above (merged record).

### `PATCH /v1/visits/{session_id}/record`
Body: partial field edits from the confirmation screen (`source: "typed"`). Returns updated record and flags.

### `POST /v1/visits/{session_id}/confirm`
Finalizes the record. Returns `{ "visit_id": "uuid", "status": "saved" }`.

### `POST /v1/sync`
Body: batch of queued items from the offline app `[{client_id, audio_base64|audio_ref, language, visit_type, recorded_at}]`. Returns per-item results. Idempotent by `client_id`.

Errors: `{"error": {"code": "STT_FAILED|LLM_PARSE_FAILED|INVALID_AUDIO|...", "message": "..."}}` with appropriate HTTP status. The app must show a friendly retry message, never a stack trace.

## 11. Mobile app spec (Flutter)

### Screens
1. **Login stub:** pick an ASHA name (no real auth for the hackathon).
2. **Beneficiary list:** assigned beneficiaries, search, tap to start a visit.
3. **Visit / Record screen:** one large mic button (push-to-talk), live status ("Listening", "Processing"), minimal text, language toggle, optional icon-only hints. Follow-up questions appear as text AND are played aloud; mic auto-opens after playback.
4. **Review & Confirm screen:** editable cards per field, low-confidence/flagged fields highlighted, risk flags banner (neutral wording), "Read back" button, Confirm button.
5. **Saved visits / Sync status:** list with synced / pending badges.

### Behavior
- Android permissions: `RECORD_AUDIO`, `INTERNET` declared in the manifest from the start. Handle denial gracefully.
- Local SQLite tables: `beneficiaries`, `drafts`, `queue` (audio file path, language, status), `visits`.
- Offline: if the network call fails, save audio and draft, mark pending, retry on connectivity change. Show a clear "saved offline" state.
- UI: large touch targets, high contrast, minimal text, supports Hindi and Kannada labels via simple i18n files. Keep language strings in one place.
- Never block the UI thread on upload. Show progress.

## 12. Evaluation plan

Create `eval/` with:
- ~30 to 50 scripted utterances (Hindi, Kannada, code-mixed) covering the schema, recorded by teammates (consenting voices only).
- Ground-truth JSON for each.
- A script that mixes in market/traffic/crowd noise at several SNR levels (`pydub` or `librosa`).
- A runner that sends clean and noisy versions through the pipeline and reports:
  - Field-level accuracy (per field and overall)
  - ID and number accuracy specifically
  - Follow-up appropriateness (asked only when needed? yes/no per case)
  - Latency per step
- Output a table (markdown/CSV) used directly in the pitch. Report honest numbers, including failures.

## 13. Privacy and safety

- Use **synthetic data only** in dev and demo. No real names, phone numbers, IDs, or recordings of real beneficiaries.
- Voice is personal data. In the pitch, state: consent screen, minimal retention (delete raw audio after processing unless needed), encryption in transit, on-device storage protection, role-based access in production.
- The LLM never diagnoses. Risk flags come from rules. UI wording for referral: "Suggest consulting ANM/doctor."
- Do not log full transcripts or audio paths with identifying info in production logs.

## 14. Repository layout

```
asha-vaani/
  SPEC.md
  backend/
    app/
      main.py
      api/ (routes)
      schemas/newborn_visit.py
      services/
        stt_gnani.py
        tts_gnani.py
        normalize.py
        extractor.py
        validator.py
        followup.py
        risk_rules.py
      config/visit_types/newborn.yaml
      prompts/ (extractor.md, followup.md)
    tests/ (normalize, validator, risk_rules, followup)
    requirements.txt
    .env.example
  mobile/                # Flutter project
    lib/
      main.dart
      models/
      services/ (api, audio, db, sync)
      screens/
      l10n/
  eval/
    audio/ (clean, noisy)
    ground_truth/
    run_eval.py
  README.md
```

## 15. Build order (milestones)

1. **Backend skeleton + schema + validator + normalizer + risk rules** with unit tests (no AI yet).
2. **STT integration** (Prisma): audio file in, transcript out. Test with sample clips.
3. **Extraction with LLM** plus validation. Test on transcripts first, then audio.
4. **Follow-up engine** (rules, then LLM ambiguity) plus Timbre TTS.
5. **Flutter app:** beneficiary list, record screen, upload, review screen.
6. **Follow-up loop in app** (play question, auto-open mic).
7. **Offline queue and sync.**
8. **Eval run, noise tests, fix worst failures.**
9. **Polish, demo video, pitch.** Stretch: supervisor flagged-cases view.

Do not start step N+1 until step N works end to end.

## 16. Rules for the Antigravity agent

- Follow this spec. If it is ambiguous, ask instead of guessing.
- Work in small steps, one feature per prompt. Run `dart analyze` / `flutter test` and `pytest` after changes.
- Do not add dependencies without listing them and why. Prefer well-maintained packages already named here.
- Do not hardcode secrets. Use `.env` and `.env.example`.
- Do not invent Gnani API details. Read docs.gnani.ai or ask me. Leave clearly marked TODOs and an interface/stub until verified.
- Keep AI logic on the backend. Keep the mobile app thin.
- Never let the LLM produce `risk_flags`, diagnoses, or default values for unspoken fields.
- Write unit tests for `normalize.py`, `validator.py`, `risk_rules.py`, `followup.py`.
- Commit after each working milestone with a clear message.
- Test audio and permissions on a real Android device, not only an emulator.

## 17. Demo script (about 60 to 90 seconds)

1. Problem in one sentence: paper registers slow ASHA workers down.
2. Worker opens a beneficiary, taps mic, says (Hindi/Kannada, code-mixed): "Beneficiary 1042, weight 2.5 kg hai, limb problem hai."
3. Structured record appears with highlighted fields.
4. App asks aloud: "Which limb?" and a combined missing-fields question. Worker answers.
5. Read-back confirmation, tap confirm. Show the low-birth-weight flag banner.
6. Show offline: airplane mode, record, see "saved offline", reconnect, see it sync.
7. Show the eval table: clean vs. noisy accuracy, with honest limitations.

## 18. Open questions to resolve early

- Exact Gnani STT/TTS endpoints, auth, audio formats, languages, credit limits. **TODO(verify)**
- Is the LLM required to be a Gnani model for this hackathon? **TODO(verify)**
- Final field list and thresholds validated by an ASHA worker/ANM. **TODO(verify)**
- Kannada and Hindi support quality on code-mixed speech. Decide after a quick STT test.
