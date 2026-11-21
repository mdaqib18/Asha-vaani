# Gnani Speech API Notes

Verified against official Gnani documentation (`docs.gnani.ai`).

## Base URL & Authentication

- **Base URL:** `https://api.vachana.ai`
- **Auth Header:** `X-API-Key-ID: <GNANI_API_KEY>` on every request
- **Optional Correlation Header:** `X-API-Request-ID` (UUID)
- Docs: [Introduction](https://docs.gnani.ai/api/introduction/introduction), [Error Reference](https://docs.gnani.ai/api/introduction/errors)

## Speech-to-Text (Prisma REST)

- **Endpoint:** `POST https://api.vachana.ai/stt/v3` (`multipart/form-data`)
- **Docs:** [STT Overview](https://docs.gnani.ai/api/STT/overview), [REST Transcription](https://docs.gnani.ai/api/STT/speech-to-text), [Supported Languages](https://docs.gnani.ai/api/STT/languages), [Limits](https://docs.gnani.ai/api/STT/limits)
- **Limits & Formats:** Max **30 seconds** per REST clip; shortest accepted is `0.1 s` (empty transcript otherwise). Format is detected from the uploaded filename extension (`wav`, `mp3`, `ogg`, `flac`, `aac`, `m4a`).
- **Languages:** `hi-IN`, `kn-IN`, `en-IN` (case-sensitive). `prisma-v3.0` also accepts comma-separated language hints (1–4) or `indic-auto`. `prisma-v2.5` accepts a single language only.
- **Chosen Defaults:**
  - `model=prisma-v3.0` — supports code-mixed language hints (`hi-IN,en-IN` and `kn-IN,en-IN`) plus domain `keyterms` (<= 200) and `topic` (<= 1600 chars) for newborn home-visit terms.
  - `format=transcribe` — writes numbers as digits and keeps English words in Latin script, pairing directly with `normalize.py`.
- **200 Response:** `{"success": true, "request_id": "...", "transcript": "...", "model": "prisma-v3.0", "detected_language_code": "hi-IN", "processing_time": 0.62, "end_to_end_latency": 0.71}` (optional `"truncated": true`).

## Text-to-Speech (Timbre REST)

- **Endpoint:** `POST https://api.vachana.ai/api/v1/tts/inference` (`application/json`)
- **Docs:** [TTS Inference](https://docs.gnani.ai/api/TTS/tts-inference), [Available Voices](https://docs.gnani.ai/api/TTS/available-voices)
- **Languages:** `hi-IN`, `kn-IN`, `en-IN`, `hi-en`, `auto` (supported by all 34 `timbre-v3.0` voices).
- **Chosen Defaults:**
  - `model=timbre-v3.0`, `voice=Lakshmi` — female voice in the `timbre-v3.0` catalog (voices are strictly model-specific and cannot be mixed between v2.5 and v3.0).
  - `audio_config`: `mp3` at `64k` bitrate, `24000` Hz, mono, for compact downloads on rural mobile connections.
  - `speed=1.0` (`timbre-v3.0` accepts only `0.8`, `1.0`, `1.2`).
- **200 Response:** Raw binary audio bytes (`audio/mpeg`).

## Error Shapes

1. **STT Envelope:** `{"success": false, "error": {"type": "<TYPE>", "message": "..."}}` (400 e.g. `EMPTY_AUDIO`, `UNSUPPORTED_AUDIO_FORMAT`, `MAX_AUDIO_DURATION_EXCEEDED`, `INVALID_LANGUAGE_CODE`; 500 `TRANSCRIPTION_FAILED`).
2. **Gateway Timeout (504):** `{"error": "Gateway Timeout", "code": "UPSTREAM_TIMEOUT", "message": "..."}`.
3. **Auth / Rate Limit (401/402/403/429):** `{"detail": {"error_code": "...", "message": "...", "status_code": ...}}` (plus FastAPI 422 `{"detail": [...]}`).
4. **TTS Flat Body (400/500):** `{"success": false, "message": "...", "status_code": 400}`.
