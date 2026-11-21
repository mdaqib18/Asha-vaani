# Asha Vaani: SPEC V2 (Improvements)

> Extends `SPEC.md`. Where the two conflict, **this file wins**. Items marked **TODO(verify)** must be checked against docs.gnani.ai or a real ASHA worker/ANM before being treated as fact. Reference this file in every agent prompt.

## 0. What changes in V2

1. Premium, simple, well-structured UI (new design system, section 2)
2. Worker home dashboard plus a statistical **Insights** tab (section 6)
3. Workers can **add new beneficiaries** and record their first case (section 3.4)
4. **Multiple visit purposes**, chosen smartly (section 4)
5. A properly structured, sync-safe database (section 5)
6. **Security visible in the UI**, backed by real mechanisms (section 7)
7. **Real-time (streaming) transcription** with Gnani (section 8)

### Build order (do not skip ahead)
1. Design system and app shell (2, 3)
2. Data layer and migrations (5)
3. Visit purpose registry plus suggestion engine (4)
4. Add-beneficiary flow (3.4)
5. Dashboard and Insights (6)
6. Security layer (7)
7. Real-time transcription (8)
8. Polish and QA pass (11)

**If short on time, cut in this order:** real-time transcription, then the Insights charts (keep the summary tiles), then extra visit purposes (keep Newborn, ANC and General illness).

---

## 1. Principles (apply to every screen)

- **One primary action per screen.** The worker should never wonder what to tap.
- **Say it with icon plus word.** Never icon-only for primary actions. Never color-only for risk.
- **Every state is designed:** empty, loading, error, offline, success, permission denied.
- **Low literacy friendly:** short labels, numbers and icons first, voice wherever possible, large type.
- **Honest UI:** never show a statistic, badge or security claim that isn't real or measured.
- **Local-first:** every screen must work offline from local data.

---

## 2. Design system ("calm clinical, warm")

### 2.1 Direction
A calm, trustworthy health tool for Indian field use: deep teal for trust, warm off-white background for reduced glare, one restrained amber accent. Flat surfaces with hairline borders instead of heavy shadows. Plenty of whitespace, left-aligned text, strong hierarchy.

### 2.2 Anti-"AI slop" rules (hard rules)
- No purple/blue gradients, no glassmorphism, no neon glows.
- No emoji as icons or decoration. No "Welcome back 👋" style copy.
- No default Material blue. No default Flutter demo look.
- No card inside card inside card. At most one level of containment.
- One elevation level only (use 1px borders, not shadow stacks).
- No centered-everything layouts. Align content to a consistent left edge and grid.
- No stock illustrations or generic hero images. Use simple line icons and real data.
- Copy must be concrete ("3 visits due today"), not fluffy ("Your journey starts here").

### 2.3 Tokens (put in `lib/theme/tokens.dart`, use everywhere, no hardcoded colors)

| Token | Hex | Use |
|---|---|---|
| `primary` | `#0B5D5E` | Primary buttons, active nav, key accents |
| `primaryContainer` | `#D6EBEA` | Subtle highlights, selected chips |
| `ink` | `#14201F` | Primary text |
| `inkMuted` | `#51615F` | Secondary text |
| `surface` | `#FAF8F4` | App background (warm off-white) |
| `surfaceRaised` | `#FFFFFF` | Cards, sheets |
| `outline` | `#E3DED5` | Borders and dividers |
| `accent` | `#C8741A` | Sparingly: highlights, one-off attention |
| `riskHigh` | `#B3261E` | High risk (always with icon + text) |
| `riskMedium` | `#9A5B00` | Needs attention |
| `riskOk` | `#1F7A4D` | Normal / synced / done |
| `info` | `#1D5E8C` | Neutral info |

Check text/background contrast >= 4.5:1 with a contrast checker before finalizing. Provide a high-contrast variant if time allows (outdoor sunlight use).

### 2.4 Typography
- Font: **Noto Sans** family, **bundled in assets** (not downloaded at runtime) so it works offline and renders **Devanagari and Kannada** correctly. Verify Hindi and Kannada glyphs on a real phone.
- Weights: Regular 400 and SemiBold 600 only.
- Sizes (sp): Display 28, Title 22, Heading 18, Body 16 (minimum for body), Label 14 (minimum for anything), Caption 13 (rare).
- Line height 1.4 or more (Indic scripts need vertical room).
- Numbers: use tabular figures for stats and measurements.
- Must survive **system font scale 130%** without clipping or overflow.

### 2.5 Layout and shape
- 4dp base grid. Spacing scale: 4, 8, 12, 16, 24, 32.
- Screen horizontal padding 16. Section gap 24.
- Corner radius: 12 (cards, inputs), 14 (buttons), fully round (chips, avatars).
- Minimum touch target 48x48dp. The mic button is 88dp.
- Icons: one consistent line-icon set (Material Symbols Rounded or Lucide), 24dp.

### 2.6 Motion
150 to 250 ms, ease-out. A gentle pulse on the mic while listening. No bounce or parallax. Respect the system "reduce motion" setting.

### 2.7 Component library (`lib/ui/`, build these first, screens only compose them)
`AppScaffold`, `PrimaryButton`, `SecondaryButton`, `TextAction`, `MicButton`, `StatTile`, `SectionHeader`, `BeneficiaryTile`, `VisitTile`, `FieldCard` (value, confidence, edit), `RiskBadge` (icon + text), `SyncChip`, `SecurityChip`, `LiveTranscript`, `FollowUpCard`, `EmptyState`, `ErrorState`, `SkeletonLoader`, `ConfirmSheet`.

### 2.8 Navigation
Bottom navigation, 4 tabs with labels: **Home**, **Beneficiaries**, **Insights**, **Settings**. A prominent "Record visit" button on Home and on every beneficiary profile (no center FAB).

### 2.9 Accessibility
Semantic labels for TalkBack on all controls, 4.5:1 contrast, no color-only meaning, error text next to the field, large hit areas, confirm destructive actions.

### 2.10 Localization
All strings in l10n files (English, Hindi, Kannada). No hardcoded strings in widgets. Language switch always reachable from the header or Settings. Test with the longest strings.

---

## 3. Screens

### 3.1 Lock / sign-in
Worker code plus PIN (backend issues a session token; **TODO** keep it simple for the hackathon). Biometric unlock after first sign-in if available. Shows the app name, a small `SecurityChip`, and nothing else. Works offline after the first sign-in.

### 3.2 Home
- Header: greeting by name (localized, plain "Namaste, Lakshmi"), language toggle, `SyncChip`.
- Three `StatTile`s: **Due today**, **Done today**, **Needs attention** (high-risk open cases). Tapping a tile opens the filtered list.
- Primary button: **Record visit**.
- **Due and overdue list**, sorted by overdue first, then risk, then due date. Each row: name, purpose due ("Newborn visit, day 7"), days overdue, `RiskBadge`.
- Empty state when nothing is due: a calm message and "Add a beneficiary".

### 3.3 Beneficiaries
- Search (name, local code, area), filter chips: **All, Pregnant women, Newborns, Children, Others**, plus a "High risk" toggle.
- `BeneficiaryTile`: initials avatar, name, type and age ("Newborn, 9 days"), next due, `RiskBadge` if any.
- Primary action: **Add beneficiary**.

### 3.4 Add beneficiary and record first case
Two entry paths on one screen:
1. **Speak (recommended):** "Naya beneficiary, Sunita, 26 saal, pregnant, 5 mahine." The backend extracts name, age/DOB, type, pregnancy months, area. Show an editable review. Worker confirms.
2. **Fill in:** 3 short steps, never more:
   - **Who:** name, sex, date of birth or age (flag "estimated"), beneficiary type
   - **Where:** area/village, household (optional), phone (optional, masked after save)
   - **Details by type:** pregnant -> LMP or months pregnant (compute EDD); newborn -> date of birth and **link mother** (search existing); child -> date of birth
3. **Consent step** (required): record that the beneficiary or guardian agreed to data collection (verbal or signed), stored as a consent record.
4. **Duplicate check** before saving (see 5.4): show "Possible match" with an option to open the existing person instead.
5. On save: offer **Record first visit now** (goes to the purpose picker with the purpose pre-suggested).

### 3.5 Beneficiary profile
Header (name, type, age, `RiskBadge`, area), next due, **Record visit** primary button, visit timeline (newest first, tap for detail), trend chart where data exists (newborn weight, BP for pregnant women/NCD). Sensitive fields masked with tap-to-reveal.

### 3.6 Visit purpose picker
Top card: **Suggested** purpose with reason ("Newborn day 7 visit is due"). Below, other valid purposes for this beneficiary type. Voice can also pick it ("BP check" -> NCD screening) with a confirmation chip. See section 4.

### 3.7 Record screen
Large `MicButton`, live transcript area (section 8), recognized-field chips that fill as the worker speaks, `FollowUpCard` when needed. Minimal text. Clear states: Ready, Listening, Processing, Needs answer, Offline (saved).

### 3.8 Review and confirm
Editable `FieldCard`s grouped by section, flagged and low-confidence fields first, risk banner with neutral wording ("Suggest consulting ANM/doctor"), **Read back** button, **Confirm** primary button. Confirmed visits become immutable (edits create amendments, see 5.3).

### 3.9 Insights
See section 6.

### 3.10 Settings and Privacy
Language, app lock (PIN/biometric), auto-lock time, sync now, storage and audio retention info, **Privacy and data** page (plain-language), sign out, about. Dev-only toggle: disable screenshot protection (for demo recording).

---

## 4. Visit purposes (registry-driven, smart)

### 4.1 Approach
Visit purposes are **configuration, not code**. Each purpose is a YAML file in `backend/app/config/visit_types/` (mirrored for the app via an API that serves the active registry and schema version). Adding a purpose = adding a YAML file plus tests. Every visit stores `visit_type_code` and `schema_version`, so old records stay valid when a form changes.

### 4.2 MVP purposes (all thresholds **TODO(verify)** with an ANM or official guidance)

| Code | Applies to | Key fields (examples) | Example rule-based flags |
|---|---|---|---|
| `newborn_home_visit` | Newborn (<= 42 days) | weight, temperature, breastfeeding, cord, jaundice, breathing rate, limb abnormality, danger signs | weight < 2.5 kg; temp >= 37.5 or < 35.5; breathing > 60/min |
| `anc_visit` | Pregnant women | gestation weeks, weight, BP, Hb, IFA tablets taken, TT/Td status, danger signs, swelling, bleeding | BP >= 140/90; Hb < 11 g/dL; danger signs present |
| `pnc_mother_visit` | Mothers after delivery | bleeding, fever, breast problems, mood, family planning counselling | heavy bleeding; fever |
| `child_growth_immunization` | Children under 5 | weight, MUAC, vaccines given/due, diarrhoea, fever | MUAC < 11.5 cm; vaccines overdue |
| `general_illness` | Anyone | symptoms, duration, temperature, action taken, referral | fever > 3 days; danger signs |
| `ncd_screening` | Adults (30+) | BP, random blood sugar, symptoms, tobacco use | BP >= 140/90; high sugar per guidance |

Stretch purposes (only if everything else works): `tb_followup`, `family_planning`.

### 4.3 Smart behavior
1. **Suggested purpose by rules:** beneficiary type + age + last visit + due schedule (e.g. newborn schedule days 3, 7, 14, 21, 28, 42 **TODO(verify)**; ANC roughly monthly **TODO(verify)**). Implemented in `due_engine.py`, writes `next_due_at` when a visit is confirmed.
2. **Voice purpose detection:** the extractor may return `detected_purpose` from speech. The UI shows it as a confirmation chip, never auto-switches silently.
3. **Shared common block** on every purpose: date, location note, general notes, referral decision. Purpose-specific fields come from its YAML.
4. **Follow-up engine unchanged in principle:** required fields from the YAML, then at most 2 follow-ups, LLM only for ambiguity. Risk flags only from deterministic rules.
5. **Multiple purposes per visit:** allow one visit to carry a primary purpose plus "also discussed" tags (stretch). Do not create separate near-duplicate forms.

### 4.4 YAML shape (example)
```yaml
code: anc_visit
schema_version: 1
name: {en: "Antenatal check", hi: "...", kn: "..."}
applies_to: [pregnant_woman]
due_rule: {interval_days: 30}
fields:
  - {key: gestation_weeks, type: int, required: true, min: 4, max: 42}
  - {key: bp_systolic, type: int, required: true, min: 60, max: 260}
  - {key: bp_diastolic, type: int, required: true, min: 30, max: 160}
  - {key: hb_g_dl, type: float, required: false, min: 3, max: 18}
risk_rules:
  - {id: high_bp, when: "bp_systolic >= 140 or bp_diastolic >= 90", flag: high_blood_pressure, severity: high}
followup_templates:
  missing_required: {en: "...", hi: "...", kn: "..."}
```
(Translations to be written and checked by a fluent speaker.)

---

## 5. Database and data management

SQLite on the device (encrypted, see 7) and SQLite on the server via SQLAlchemy plus **Alembic migrations** (Postgres-ready). Device migrations via `onUpgrade`. All primary keys are **client-generated UUIDs** so records can be created offline.

### 5.1 Tables

| Table | Key columns |
|---|---|
| `workers` | id, worker_code, name, language_pref, area_ids, created_at |
| `areas` | id, name, code |
| `households` | id, area_id, note |
| `beneficiaries` | id, local_code (short numeric, unique per worker), external_id (optional, e.g. government ID), worker_id, area_id, household_id, full_name, sex, dob, dob_is_estimated, beneficiary_type, mother_id (self-reference), phone_enc, consent_id, status (`active`, `transferred`, `closed`), risk_level (`none`, `watch`, `high`; derived cache), last_visit_at, next_due_at, created_at, updated_at, deleted_at, version |
| `pregnancies` | id, beneficiary_id, lmp_date, edd_date, gravida, parity, outcome, status |
| `visit_types` | code, schema_version, name_i18n, active |
| `visits` | id, client_id, beneficiary_id, worker_id, visit_type_code, schema_version, visited_at, status (`draft`, `confirmed`, `amended`), payload_json, risk_flags_json, referral_suggested, next_due_at, transcript_text, language, input_method (`voice`, `typed`, `mixed`), started_at, confirmed_at, updated_at, version |
| `visit_measurements` | id, visit_id, beneficiary_id, key, value_num, unit, measured_at (normalized numbers for charts and trends) |
| `visit_amendments` | id, visit_id, changed_by, changes_json, reason, created_at |
| `followups` | id, visit_id, question_text, target_fields, answer_text, created_at |
| `audio_assets` | id, visit_id, path, duration_ms, state (`local`, `uploaded`, `deleted`), delete_after |
| `consents` | id, beneficiary_id, kind, given_by (`self`, `guardian`), method (`verbal`, `signed`), policy_version, given_at |
| `sync_queue` | id, entity, entity_id, op, attempts, last_error, created_at |
| `audit_log` | id, actor_id, action, entity, entity_id, device_id, at (append-only) |

### 5.2 Smart design choices
- **Hybrid storage:** common, queryable columns are real columns; purpose-specific content lives in `payload_json` with `schema_version`. Numbers needed for charts and rules are **also written to `visit_measurements`** on confirm.
- **Derived cache fields** (`last_visit_at`, `next_due_at`, `risk_level`) are updated in the same transaction that confirms a visit, so dashboard queries are cheap.
- **Soft delete** (`deleted_at`), never hard delete patient rows from the app.
- **Indexes:** `beneficiaries(worker_id, status, next_due_at)`, `beneficiaries(worker_id, local_code)` unique, `visits(beneficiary_id, visited_at DESC)`, `visits(worker_id, visited_at)`, `visit_measurements(beneficiary_id, key, measured_at)`.
- **Local codes:** per-worker sequential short codes (the "Beneficiary 1042" the worker speaks). Generate offline using a per-device counter range reserved by the server on sign-in to avoid collisions (**TODO**: simple version = prefix with a device-unique number, document the limitation).

### 5.3 Immutability and corrections
Confirmed visits are **immutable**. A correction creates a `visit_amendments` row and updates the visit status to `amended`, with the change history visible in the visit detail. This gives trust and an audit trail.

### 5.4 Duplicate detection (on add beneficiary)
Normalize names (lowercase, strip honorifics and spaces, transliteration-tolerant), then compare against active beneficiaries in the same area: similar name (fuzzy, e.g. `rapidfuzz` on the server, simple edit distance on device) **and** DOB within about 1 year or same phone. Show candidates; never auto-merge.

### 5.5 Sync
- Idempotent upserts keyed by UUID plus `client_id`.
- Beneficiaries: last-write-wins by `updated_at` and `version`. Visits: append-only (conflicts impossible except amendments).
- `sync_queue` retries with backoff; show per-item state. Audio uploads after record sync; delete local audio per retention rule once the server confirms.

### 5.6 Retention
Raw audio: delete after the visit is confirmed and synced, or after `AUDIO_RETENTION_DAYS` (default 7), whichever first. Transcript text is kept with the visit. Make this behavior match what the Privacy page says.

---

## 6. Statistical dashboard (Insights tab, plus Home tiles)

All stats are computed **locally from SQLite** so they work offline. The backend exposes mirrored endpoints for a later supervisor view.

### 6.1 Metrics (define precisely, show only what is real)
| Metric | Definition |
|---|---|
| Visits done | Confirmed visits in the period |
| Due / overdue | Active beneficiaries with `next_due_at` today / before today |
| Coverage | Active beneficiaries with >= 1 confirmed visit in the last 30 days, divided by all active beneficiaries |
| High-risk open cases | Beneficiaries with `risk_level = high` |
| Referrals suggested | Confirmed visits with `referral_suggested = true` |
| Avg record time | Mean of (confirmed_at - started_at) for voice visits, measured by the app |
| Voice share | Voice or mixed visits divided by all visits |
| Follow-up rate | Visits that needed at least one follow-up |

### 6.2 Screens and charts (`fl_chart` or similar)
- Period switch: **Today, 7 days, 30 days**.
- Summary tiles (the metrics above, max 4 visible at once).
- **Visits per day** (bar chart).
- **Visits by purpose** (horizontal bars, not a pie).
- **Risk flags by type** (horizontal bars with the risk icon).
- **Due list** (compact).
- Each chart has a text summary line and an empty state.

### 6.3 Honesty rules
- "Time saved" is shown **only** if a baseline (minutes per paper record) is entered in Settings. Otherwise show the measured average only.
- Demo data is generated by a seed script and clearly labeled **"Demo data"** in the UI when active. Never present seeded numbers as real impact in the pitch.

### 6.4 Endpoints
`GET /v1/stats/summary?period=`, `GET /v1/stats/visits-timeseries?period=`, `GET /v1/stats/by-purpose?period=`, `GET /v1/stats/risk-breakdown?period=`, `GET /v1/stats/due-list`.

---

## 7. Security shown in the UI (and actually implemented)

**Rule: a security claim may appear in the UI only if the mechanism behind it exists and is tested.**

| UI element | Real mechanism required |
|---|---|
| Lock screen, PIN, biometric | `local_auth` plus PIN hash stored in secure storage |
| Auto-lock after inactivity/background (default 60 s) | App lifecycle observer; relock and clear sensitive in-memory state |
| "Encrypted on this device" chip | Encrypted local DB (SQLCipher-compatible package, e.g. `sqflite_sqlcipher` or `drift` with encryption), key in Android Keystore via `flutter_secure_storage` |
| Screenshot/recents protection | `FLAG_SECURE` (use a maintained plugin or a small platform channel; **TODO(verify)** package health). Add a dev-only off switch for demo recording. |
| Masked phone and external ID with tap-to-reveal | Masking in the UI layer; each reveal writes `audit_log` |
| Consent step before recording | `consents` row required before a visit or new beneficiary can be saved |
| "Audio deleted after processing" | Retention job from 5.6, tested |
| `SyncChip`: "Encrypted, synced 2 min ago" | HTTPS only; chip state derived from real `sync_queue` status |
| "Signed in as Lakshmi (ASHA)" plus sign-out | Session token cleared on sign-out; local DB stays locked |
| Visit audit line ("Recorded by, confirmed at, amended") | Data from `visits`, `visit_amendments`, `audit_log` |
| Privacy and data page | Plain-language: what is collected, where it is stored, how long, who can see it, how to delete |

Backend: all provider keys (Gnani, LLM) stay on the server, **never in the APK**. HTTPS only. Short-lived session tokens. Rate-limit per worker. Do not log transcripts, names or audio in production logs.

Where it appears: a small lock-icon `SecurityChip` in the app header (opens the Privacy page), the lock screen, masked fields, the consent step, Settings, and the sync status.

---

## 8. Real-time transcription (Gnani streaming)

### 8.1 Decision
**Yes, add it, as a hybrid.** Live captions let the worker see mishearings (especially IDs and numbers) immediately and make the app feel instant. But rural connectivity is unreliable, so recording to a local file always runs in parallel, and the batch path from SPEC.md remains the fallback.

### 8.2 What Gnani provides (**TODO(verify)** all details at docs.gnani.ai, "STT Realtime PCM specification")
- WebSocket endpoint `wss://api.vachana.ai/stt/v3/stream`, authenticated with an API-key header.
- Audio must be **raw PCM** frames (no WAV/MP3 container mid-stream), 1,024 bytes per frame (512 samples of 16-bit at 16 kHz), sent at **real-time pace** (one frame every 32 ms at 16 kHz). Do not buffer and burst.
- Server sends a `connected` event, then transcript events. Language can be fixed or auto-detected (auto-detect is streaming only).
- Official Python client: `gnani-vachana` (`GnaniSTTStreamClient`).

### 8.3 Architecture
```
Flutter app --(WebSocket, PCM16 16kHz mono)--> FastAPI /v1/stream
FastAPI: re-chunk to 1024-byte frames, pace at 32 ms --> Gnani STT stream
Gnani transcript events --> FastAPI --> app: {"type":"partial"|"final", "text":...}
On end of utterance / stop: final transcript -> normalize -> LLM extraction -> validation
FastAPI --> app: {"type":"fields", ...} then {"type":"followup", ...} if needed
```
- **The app never talks to Gnani directly** (the API key stays on the server).
- Flutter side: `record` package stream mode with PCM16 output at 16 kHz mono. Send each chunk over the WebSocket. In parallel, write the same audio to a local file.
- **Do not run the LLM on partial text.** Partials may change. Extract on final transcript segments or when the worker stops (extraction on the full final text is the source of truth).
- Optional: show recognized-field chips updating after each pause (end-of-utterance), not on every partial.

### 8.4 Messages (app <-> backend)
Client -> server: first message JSON `{"type":"start","session_id","language","visit_type","beneficiary_id"}`, then binary audio frames, then `{"type":"stop"}`.
Server -> client:
```json
{"type":"partial","text":"..."}
{"type":"final","text":"...","utterance_id":1}
{"type":"fields","record":{...},"flags":[...]}
{"type":"followup","question_text":"...","question_audio_url":"...","target_fields":["..."]}
{"type":"error","code":"STT_STREAM_FAILED","message":"..."}
```

### 8.5 UI behavior
- `LiveTranscript`: partial text in muted ink, finalized text in full ink, numbers and IDs highlighted.
- Level meter while listening. Clear "Listening / Processing" state.
- If the stream drops: keep recording locally, show "Live captions paused, still recording", and process the saved audio via the batch endpoint afterward.
- Language: use the worker's language by default, with an "Auto-detect" toggle for code-mixed speech (**test both**, since fixed language may be more reliable).

### 8.6 Testing
Test on a real phone on a weak network. Measure first-partial latency and final-transcript latency. Compare field accuracy against the batch path using the eval set from SPEC.md.

---

## 9. Backend API additions

`POST/GET/PATCH /v1/beneficiaries`, `GET /v1/beneficiaries/{id}`, `GET /v1/beneficiaries/{id}/visits`, `POST /v1/beneficiaries/check-duplicate`, `GET /v1/visit-types`, `GET /v1/beneficiaries/{id}/suggested-purpose`, `POST /v1/beneficiaries/from-audio` (speak-to-add), stats endpoints (6.4), `WS /v1/stream` (8.4), `POST /v1/auth/login`. Existing visit endpoints take `visit_type_code` and return the schema version used.

---

## 10. Antigravity prompt sequence (paste one at a time, verify before the next)

1. **Design system:** "Read SPEC_V2.md sections 1 and 2. Create `lib/theme/tokens.dart`, the theme, bundled Noto Sans fonts (Latin, Devanagari, Kannada) and the component library in `lib/ui/` listed in 2.7. Build a hidden 'gallery' screen showing every component in every state. Follow the anti-slop rules exactly. Do not change existing screens yet."
2. **App shell and Home:** "Implement navigation (2.8), Lock screen (3.1) and Home (3.2) using only components from `lib/ui/`. All strings via l10n (en, hi, kn)."
3. **Data layer:** "Implement section 5 on the device (migrations from the existing schema) and on the backend (Alembic). Include unit tests for the due engine, derived cache updates and duplicate detection."
4. **Visit registry:** "Implement section 4: YAML registry, `/v1/visit-types`, suggested purpose, purpose picker (3.6). Convert the existing newborn form to a YAML purpose, then add ANC and General illness."
5. **Beneficiaries:** "Implement 3.3 to 3.5 including the add-beneficiary flow with consent and duplicate check, then speak-to-add."
6. **Insights:** "Implement section 6 with local SQLite queries, charts, empty states and the demo-data seed script labeled 'Demo data'."
7. **Security:** "Implement section 7 exactly. Show a security element only when its mechanism exists. Add the dev-only screenshot-protection toggle."
8. **Real-time STT:** "Implement section 8. Keep the batch path working as the fallback. Verify the Gnani realtime spec at docs.gnani.ai; do not guess frame details."
9. **Polish:** "Run the checklist in section 11 and fix everything that fails."

Rules for every prompt: follow the spec, ask if ambiguous, add tests for logic, no new dependencies without listing them, no secrets in the app, commit after each working step.

---

## 11. Polish and QA checklist (definition of done)

- [ ] All screens use tokens and components only (no hardcoded colors, sizes or strings).
- [ ] Works at font scale 130% and on a 360x640 screen, with no overflow or clipped Hindi/Kannada text.
- [ ] Contrast checked (4.5:1) for all text and badges. Risk is never color-only.
- [ ] Every screen has empty, loading, error and offline states.
- [ ] TalkBack labels on all controls. Touch targets >= 48dp.
- [ ] Airplane-mode test: add beneficiary, record visit, see "saved offline", reconnect, see it sync.
- [ ] No fake numbers on Insights. Demo data labeled.
- [ ] Every security claim in the UI has a real mechanism (checked against section 7).
- [ ] No API keys in the APK (decompile or search the build to confirm).
- [ ] Visit confirmation is immutable. Amendments are visible in the history.
- [ ] Live captions drop and recover gracefully on a weak network.
- [ ] Demo flow rehearsed end to end on a real phone: sign in, add beneficiary by voice, record a visit with live captions, answer a follow-up, confirm, see the stats update.
