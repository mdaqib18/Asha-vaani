# Asha Vaani — Demo Script, Architecture Summary & Pitch Guide

> Aligned with `SPEC.md` (`§4`, `§12`, `§13`, `§17`) and verified Milestone 8 metrics.

## 1. One-Line Positioning

Asha Vaani is a **voice capture layer** that turns ASHA home-visit speech (Hindi, Kannada, and English code-mixed) into validated structured records matching existing registers — **not** a replacement for government portals and **not** an LLM diagnostic tool.

---

## 2. 60–90 Second Live Demo Script (`SPEC.md §17`)

1. **Problem (0:00–0:08):**
   *"ASHA workers conduct newborn home visits and have to fill paper registers after hours from memory. Writing slows them down; speaking is natural."*
2. **Capture in Mixed Speech (0:08–0:25):**
   - Select **Sunita Devi (`asha_001`)** on the Login screen (note the consent/synthetic-data footer and **EN / हिं / ಕನ್** language toggle).
   - Tap **Baby of Sunita (`1042`) -> Start visit**.
   - Hold **Hold to Speak** and say:
     *"Beneficiary 1042, weight 2.5 kg hai, aur limb problem hai."*
   - Wait for **Listening... -> Processing...** (~2–4s): show the extracted fields & transcript.
3. **Smart Two-Tier Follow-up Loop (0:25–0:45):**
   - App automatically plays the combined Hindi/Kannada **missing required fields** question via Gnani Timbre TTS and auto-opens the mic:
     *"Temperature 36.8, exclusive breastfeeding, cord clean dry, aur jaundice nahi hai."*
   - Next, backend triggers the **LLM ambiguity follow-up** (`"Which limb?"` — never re-asking already filled fields). Answer: *"Left leg mein swelling hai."*
4. **Read-Back, Safety Nets & Confirm (0:45–1:00):**
   - App opens **Review & Confirm**: show `Left leg` filled, `needs_confirmation` highlight, and **"Suggest consulting ANM/doctor"** banner (computed by deterministic YAML rules, never the LLM).
   - Tap **Read Back** -> plays spoken TTS confirmation of ID, weight, and temperature -> tap **Confirm & Save**.
5. **Offline Queue & Auto-Sync (1:00–1:12):**
   - Toggle Airplane Mode on the phone -> open Beneficiary `1043` -> record visit -> tap stop -> show **"Saved offline"** card + `Pending` badge on **Saved Visits**.
   - Turn internet back on -> show automatic sync moving the recording to **`Ready to review`**.
6. **ANM Supervisor View & Honest Eval (1:12–1:25):**
   - Open **Flagged Cases (ANM)** from the menu -> tap the flagged visit to inspect vitals and risk chips across workers.
   - Show the Milestone 8 Clean vs. Noisy eval slide below.

---

## 3. Honest Evaluation Table (`eval/results/eval_report.md`)

- **Pipeline tested:** `gemini-3.5-flash-lite` + Gnani `prisma-v3.0` STT (`0` API errors across all 84 live runs).
- **Audio provenance:** 36 scripted synthetic utterances (`hi`, `kn`, `codemix_hi`, `codemix_kn`); 12-case balanced audio subset (`4 hi`, `4 kn`, `4 code-mixed`) synthesized via Gnani `timbre-v3.0` TTS and mixed at active-speech SNR (`market_20db`, `traffic_10db`, `crowd_5db`).

| Condition | Cases | Errors | Field Acc | ID Acc | Number Acc | Risk Acc | Referral Acc | Follow-up Approp. | Mean STT (s) | Mean LLM (s) | Mean Total (s) |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| `transcript` | 36 | 0 | 98.1% (318/324) | 100.0% (36/36) | 100.0% (79/79) | 83.3% | 100.0% | 100.0% (36/36) | 0.00 | 1.92 | 2.02 |
| `clean` | 12 | 0 | 97.2% (105/108) | 100.0% (12/12) | 96.2% (25/26) | 75.0% | 100.0% | 100.0% (12/12) | 1.53 | 3.19 | 4.73 |
| `market_20db` | 12 | 0 | 97.2% (105/108) | 100.0% (12/12) | 96.2% (25/26) | 75.0% | 100.0% | 100.0% (12/12) | 1.86 | 2.08 | 3.94 |
| `traffic_10db` | 12 | 0 | 97.2% (105/108) | 100.0% (12/12) | 96.2% (25/26) | 75.0% | 100.0% | 100.0% (12/12) | 1.82 | 2.00 | 3.83 |
| `crowd_5db` | 12 | 0 | 94.4% (102/108) | 91.7% (11/12) | 96.2% (25/26) | 66.7% | 91.7% | 83.3% (10/12) | 2.11 | 2.17 | 4.52 |

### Honest Limitations & Why Safety Nets Matter
- Audio subset clips were TTS-synthesized (`timbre-v3.0`); field trials with real ASHA speakers are the next validation step.
- Under heavy **5 dB crowd babble**, Kannada ASR flipped negation twice (`kn_01`, `kn_03`) and misheard ID `1057` as `1507` (automatically caught by our `unknown_beneficiary` validator).
- When TTS/STT dropped `"F"` in `mix_08` (`101.3 degree`), the deterministic range check (`out_of_range`) flagged `temperature_c` for confirmation instead of silently altering it.

---

## 4. Privacy & Clinical Safety Talking Points (`SPEC.md §13`)

- **Synthetic data only:** All beneficiaries, IDs, and transcripts are synthetic (`1042`, `1043`, `2011`).
- **Voice data governance:** Explicit consent before recording, minimal audio retention (delete raw audio after confirmation in production), TLS encryption in transit, device-level encrypted storage, and role-based ASHA/ANM access.
- **No LLM diagnosis:** `risk_flags` and `referral_suggested` come strictly from deterministic rules in `config/visit_types/newborn.yaml`; UI displays **"Suggest consulting ANM/doctor."**

---

## 5. Real Phone & Backend Deploy Checklist

1. **Deploy backend** via `render.yaml` (Render) or `backend/Procfile` (Railway) and set `GNANI_API_KEY` and `LLM_API_KEY` in the dashboard.
2. **Verify health:** `GET https://<your-app>.onrender.com/v1/health` -> `{"status":"ok"}`.
3. **Install debug APK on Android phone:**
   ```powershell
   adb install mobile\build\app\outputs\flutter-apk\app-debug.apk
   ```
   (Or run over USB with `adb reverse tcp:8000 tcp:8000` if using local `uvicorn`.)
4. **Point app to server:** Tap the settings icon (`Server Settings`) on the Login screen, enter the backend URL, and tap **Test Connection**.
