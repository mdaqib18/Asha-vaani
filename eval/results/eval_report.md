# Asha Vaani — Evaluation Report (Milestone 8)

- **Generated (UTC):** 2026-11-21T17:52:58.112562+00:00
- **LLM Provider / Model:** `gemini` / `gemini-3.5-flash-lite`
- **STT / TTS Models:** `prisma-v3.0` / `timbre-v3.0`
- **Audio Provenance:** Clean clips (12=synthesized_tts) + deterministic 16 kHz active-SNR noise mixes (`market_20db`, `traffic_10db`, `crowd_5db`).

## 1. Overall Accuracy & Latency by Condition

| Condition | Cases | Errors | Field Acc | ID Acc | Number Acc | Risk Acc | Referral Acc | Follow-up Approp. | Mean STT (s) | Mean LLM (s) | Mean Total (s) |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| `transcript` | 36 | 0 | 98.1% (318/324) | 100.0% (36/36) | 100.0% (79/79) | 83.3% | 100.0% | 100.0% (36/36) | 0.00 | 1.92 | 2.02 |
| `clean` | 12 | 0 | 97.2% (105/108) | 100.0% (12/12) | 96.2% (25/26) | 75.0% | 100.0% | 100.0% (12/12) | 1.53 | 3.19 | 4.73 |
| `market_20db` | 12 | 0 | 97.2% (105/108) | 100.0% (12/12) | 96.2% (25/26) | 75.0% | 100.0% | 100.0% (12/12) | 1.86 | 2.08 | 3.94 |
| `traffic_10db` | 12 | 0 | 97.2% (105/108) | 100.0% (12/12) | 96.2% (25/26) | 75.0% | 100.0% | 100.0% (12/12) | 1.82 | 2.00 | 3.83 |
| `crowd_5db` | 12 | 0 | 94.4% (102/108) | 91.7% (11/12) | 96.2% (25/26) | 66.7% | 91.7% | 83.3% (10/12) | 2.11 | 2.17 | 4.52 |

## 2. Per-Field Accuracy by Condition

| Field | `transcript` | `clean` | `market_20db` | `traffic_10db` | `crowd_5db` |
|---|---:|---:|---:|---:|---:|
| `beneficiary_id` | 100.0% | 100.0% | 100.0% | 100.0% | 91.7% |
| `baby_weight_kg` | 100.0% | 100.0% | 100.0% | 100.0% | 100.0% |
| `temperature_c` | 100.0% | 91.7% | 91.7% | 91.7% | 91.7% |
| `breastfeeding` | 100.0% | 100.0% | 100.0% | 100.0% | 100.0% |
| `cord_status` | 100.0% | 100.0% | 100.0% | 100.0% | 100.0% |
| `jaundice` | 100.0% | 100.0% | 100.0% | 100.0% | 100.0% |
| `breathing_rate_per_min` | 100.0% | 100.0% | 100.0% | 100.0% | 100.0% |
| `limb_abnormality` | 100.0% | 100.0% | 100.0% | 100.0% | 83.3% |
| `danger_signs` | 83.3% | 83.3% | 83.3% | 83.3% | 83.3% |

## 3. Accuracy by Language / Code-Mix Bucket

| Bucket | Condition | Cases | Field Acc | ID Acc | Number Acc | Follow-up Approp. |
|---|---|---:|---:|---:|---:|---:|
| `codemix_hi` | `transcript` | 6 | 100.0% | 100.0% | 100.0% | 100.0% |
| `codemix_hi` | `clean` | 2 | 100.0% | 100.0% | 100.0% | 100.0% |
| `codemix_hi` | `market_20db` | 2 | 100.0% | 100.0% | 100.0% | 100.0% |
| `codemix_hi` | `traffic_10db` | 2 | 100.0% | 100.0% | 100.0% | 100.0% |
| `codemix_hi` | `crowd_5db` | 2 | 100.0% | 100.0% | 100.0% | 100.0% |
| `codemix_kn` | `transcript` | 6 | 96.3% | 100.0% | 100.0% | 100.0% |
| `codemix_kn` | `clean` | 2 | 94.4% | 100.0% | 83.3% | 100.0% |
| `codemix_kn` | `market_20db` | 2 | 94.4% | 100.0% | 83.3% | 100.0% |
| `codemix_kn` | `traffic_10db` | 2 | 94.4% | 100.0% | 83.3% | 100.0% |
| `codemix_kn` | `crowd_5db` | 2 | 94.4% | 100.0% | 83.3% | 100.0% |
| `hi` | `transcript` | 12 | 99.1% | 100.0% | 100.0% | 100.0% |
| `hi` | `clean` | 4 | 97.2% | 100.0% | 100.0% | 100.0% |
| `hi` | `market_20db` | 4 | 97.2% | 100.0% | 100.0% | 100.0% |
| `hi` | `traffic_10db` | 4 | 97.2% | 100.0% | 100.0% | 100.0% |
| `hi` | `crowd_5db` | 4 | 97.2% | 100.0% | 100.0% | 100.0% |
| `kn` | `transcript` | 12 | 97.2% | 100.0% | 100.0% | 100.0% |
| `kn` | `clean` | 4 | 97.2% | 100.0% | 100.0% | 100.0% |
| `kn` | `market_20db` | 4 | 97.2% | 100.0% | 100.0% | 100.0% |
| `kn` | `traffic_10db` | 4 | 97.2% | 100.0% | 100.0% | 100.0% |
| `kn` | `crowd_5db` | 4 | 88.9% | 75.0% | 100.0% | 50.0% |

## 4. Per-Step Latency Breakdown (Seconds)

| Condition | STT Mean / p95 | LLM Extract Mean / p95 | Validate+Risk Mean / p95 | Follow-up Mean / p95 | Total Mean / p95 |
|---|---:|---:|---:|---:|---:|
| `transcript` | 0.00 / 0.00 | 1.92 / 3.80 | 0.000 / 0.001 | 0.10 / 0.94 | 2.02 / 3.80 |
| `clean` | 1.53 / 3.02 | 3.19 / 8.14 | 0.000 / 0.000 | 0.00 / 0.00 | 4.73 / 9.55 |
| `market_20db` | 1.86 / 4.74 | 2.08 / 3.90 | 0.000 / 0.001 | 0.00 / 0.00 | 3.94 / 6.70 |
| `traffic_10db` | 1.82 / 3.80 | 2.00 / 4.45 | 0.000 / 0.001 | 0.00 / 0.00 | 3.83 / 5.88 |
| `crowd_5db` | 2.11 / 8.19 | 2.17 / 4.68 | 0.000 / 0.001 | 0.24 / 1.83 | 4.52 / 10.99 |

## 5. Failure Analysis & Honest Limitations

- **`transcript` / `mix_10`** (codemix_kn): `danger_signs` (hallucinated: exp=[], got=['not_feeding']); `risk_flags` (exp=['limb_abnormality', 'low_birth_weight', 'not_feeding'], got=['danger_sign:not_feeding', 'limb_abnormality', 'low_birth_weight', 'not_feeding']) — transcript: "Beneficiary 2014, weight 1800 grams ide, temperature 36.8 C, baby not feeding, cord cle..."
- **`transcript` / `mix_12`** (codemix_kn): `danger_signs` (mismatch: exp=['convulsions'], got=['convulsions', 'fast_breathing']); `risk_flags` (exp=['danger_sign:convulsions'], got=['danger_sign:convulsions', 'danger_sign:fast_breathing']) — transcript: "Beneficiary 9999, weight 2.8 kg ide, temperature 36.9 C, breastfeeding exclusive ide, c..."
- **`transcript` / `hi_09`** (hi): `danger_signs` (hallucinated: exp=[], got=['not_feeding']); `risk_flags` (exp=['cord_infection', 'fever', 'low_birth_weight', 'not_feeding'], got=['cord_infection', 'danger_sign:not_feeding', 'fever', 'low_birth_weight', 'not_feeding']) — transcript: "लाभार्थी 9999, वजन 2.3 किलो, तापमान 37.6 डिग्री, बच्चा बिल्कुल दूध नहीं पी रहा है, नाल ..."
- **`transcript` / `kn_03`** (kn): `danger_signs` (hallucinated: exp=[], got=['pus_umbilicus']); `risk_flags` (exp=['cord_infection', 'fever', 'jaundice'], got=['cord_infection', 'danger_sign:pus_umbilicus', 'fever', 'jaundice']) — transcript: "ಫಲಾನುಭವಿ 1057, ತೂಕ 2.6 ಕೆಜಿ, ತಾಪಮಾನ 100.4 ಫ್ಯಾರನ್ಹೀಟ್, ಕೇವಲ ತಾಯಿ ಹಾಲು ಕುಡಿಯುತ್ತಿದೆ, ಹೊಕ..."
- **`transcript` / `kn_07`** (kn): `danger_signs` (mismatch: exp=['lethargy'], got=['lethargy', 'fast_breathing']); `risk_flags` (exp=['cord_infection', 'danger_sign:lethargy', 'fast_breathing'], got=['cord_infection', 'danger_sign:fast_breathing', 'danger_sign:lethargy', 'fast_breathing']) — transcript: "ಫಲಾನುಭವಿ 1043, ತೂಕ 3.0 ಕೆಜಿ, ತಾಪಮಾನ 37.1 ಡಿಗ್ರಿ, ಕೇವಲ ತಾಯಿ ಹಾಲು ಕುಡಿಯುತ್ತಿದೆ, ಹೊಕ್ಕಳುಬಳ..."
- **`transcript` / `kn_09`** (kn): `danger_signs` (hallucinated: exp=[], got=['not_feeding']); `risk_flags` (exp=['limb_abnormality', 'not_feeding'], got=['danger_sign:not_feeding', 'limb_abnormality', 'not_feeding']) — transcript: "ಫಲಾನುಭವಿ 9999, ತೂಕ 2.7 ಕೆಜಿ, ತಾಪಮಾನ 36.6 ಡಿಗ್ರಿ, ಮಗು ಹಾಲು ಕುಡಿಯುತ್ತಿಲ್ಲ, ಹೊಕ್ಕಳುಬಳ್ಳಿ ಸ..."
- **`clean` / `mix_08`** (codemix_kn): `temperature_c` (mismatch: exp=38.5, got=101.3); `risk_flags` (exp=['cord_infection', 'fast_breathing', 'fever', 'low_birth_weight'], got=['cord_infection', 'fast_breathing', 'low_birth_weight']); `validation_flags` (exp=[], got=[('temperature_c', 'out_of_range')]) — transcript: "ಬೆನಿಫಿಷರಿ 1043, weight 2.3 kg, temperature 101.35 ಡಿ. breastfeeding partial ID, cord pu..."
- **`clean` / `hi_03`** (hi): `danger_signs` (hallucinated: exp=[], got=['pus_umbilicus']); `risk_flags` (exp=['cord_infection', 'fever', 'jaundice'], got=['cord_infection', 'danger_sign:pus_umbilicus', 'fever', 'jaundice']) — transcript: "लाभार्थी 1057, बच्चे का वजन 2.7 kg, तापमान 100.4 Fahrenheit। केवल माँ का दूध पी रहा है।..."
- **`clean` / `kn_03`** (kn): `danger_signs` (hallucinated: exp=[], got=['pus_umbilicus']); `risk_flags` (exp=['cord_infection', 'fever', 'jaundice'], got=['cord_infection', 'danger_sign:pus_umbilicus', 'fever', 'jaundice']) — transcript: "ಫಲಾನುಭವಿ 1057 ತು. ತಾಯಿ 2.6 kg, ತಾಪಮಾನ 100.4 Fahrenheit. ಕೇವಲ ತಾಯಿ ಹಾಲು ಕುಡಿಯುತ್ತಿದೆ. ಹೊ..."
- **`market_20db` / `mix_08`** (codemix_kn): `temperature_c` (mismatch: exp=38.5, got=101.3); `risk_flags` (exp=['cord_infection', 'fast_breathing', 'fever', 'low_birth_weight'], got=['cord_infection', 'fast_breathing', 'low_birth_weight']); `validation_flags` (exp=[], got=[('temperature_c', 'out_of_range')]) — transcript: "beneficiary 1043, weight 2.3 kg, ID temperature 101.3 degree. breastfeeding partial ID,..."
- **`market_20db` / `hi_03`** (hi): `danger_signs` (hallucinated: exp=[], got=['pus_umbilicus']); `risk_flags` (exp=['cord_infection', 'fever', 'jaundice'], got=['cord_infection', 'danger_sign:pus_umbilicus', 'fever', 'jaundice']) — transcript: "लाभार्थी 1057, बच्चे का वजन 2.7 kg, तापमान 100.4 Fahrenheit। केवल माँ का दूध पी रहा है।..."
- **`market_20db` / `kn_03`** (kn): `danger_signs` (hallucinated: exp=[], got=['pus_umbilicus']); `risk_flags` (exp=['cord_infection', 'fever', 'jaundice'], got=['cord_infection', 'danger_sign:pus_umbilicus', 'fever', 'jaundice']) — transcript: "ಫಲಾನುಭವಿ 1057, ತಾಯಿ 2.6 kg, ತಾಪಮಾನ 100.4 Fahrenheit. ಕೇವಲ ತಾಯಿ ಹಾಲು ಕುಡಿಯುತ್ತದೆ. ಹೊಕ್ಕಳ..."
- **`traffic_10db` / `mix_08`** (codemix_kn): `temperature_c` (mismatch: exp=38.5, got=101.3); `risk_flags` (exp=['cord_infection', 'fast_breathing', 'fever', 'low_birth_weight'], got=['cord_infection', 'fast_breathing', 'low_birth_weight']); `validation_flags` (exp=[], got=[('temperature_c', 'out_of_range')]) — transcript: "beneficiary 1043, weight 2.3 kg, temperature 101.3 degree. breastfeeding partial ID, co..."
- **`traffic_10db` / `hi_03`** (hi): `danger_signs` (hallucinated: exp=[], got=['pus_umbilicus']); `risk_flags` (exp=['cord_infection', 'fever', 'jaundice'], got=['cord_infection', 'danger_sign:pus_umbilicus', 'fever', 'jaundice']) — transcript: "लाभार्थी 1057, बच्चे का वजन 2.7 kg, तापमान 100.4 Fahrenheit। केवल माँ का दूध पी रहा है।..."
- **`traffic_10db` / `kn_03`** (kn): `danger_signs` (hallucinated: exp=[], got=['fever', 'pus_umbilicus']); `risk_flags` (exp=['cord_infection', 'fever', 'jaundice'], got=['cord_infection', 'danger_sign:fever', 'danger_sign:pus_umbilicus', 'fever', 'jaundice']) — transcript: "ಫಲಾನುಭವಿ 1057, ತಾಯಿ 2.6 kg, ತಾಪಮಾನ 100.4 Fahrenheit. ಕೇವಲ ತಾಯಿ ಹಾಲು ಕುಡಿಯುತ್ತದೆ. ಹೊಕ್ಕಳ..."
- **`crowd_5db` / `mix_08`** (codemix_kn): `temperature_c` (mismatch: exp=38.5, got=101.3); `risk_flags` (exp=['cord_infection', 'fast_breathing', 'fever', 'low_birth_weight'], got=['cord_infection', 'fast_breathing', 'low_birth_weight']); `validation_flags` (exp=[], got=[('temperature_c', 'out_of_range')]) — transcript: "beneficiary 1043, weight 2.3 kg, temperature 101.3 degree. breastfeeding partial ID, co..."
- **`crowd_5db` / `hi_03`** (hi): `danger_signs` (hallucinated: exp=[], got=['pus_umbilicus']); `risk_flags` (exp=['cord_infection', 'fever', 'jaundice'], got=['cord_infection', 'danger_sign:pus_umbilicus', 'fever', 'jaundice']) — transcript: "लाभार्थी 1057, बच्चे का वजन 2.7 kg, तापमान 100.4 Fahrenheit। केवल माँ का दूध पी रहा है,..."
- **`crowd_5db` / `kn_01`** (kn): `limb_abnormality` (mismatch: exp={'present': False, 'location': None}, got={'present': True, 'location': 'unspecified'}); `risk_flags` (exp=[], got=['limb_abnormality']); `followup` (unnecessary follow-up (llm_ambiguity: ['limb_abnormality.location'])) — transcript: "ಫಲಾನುಭವಿ ಸಂಖ್ಯೆ 1042. ಮಗುವಿನ ತೂಕ 2.9 kg. ತಾಪಮಾನ 36.7 degree Celsius. ಕೇವಲ ತಾಯಿ ಹಾಲು ಕುಡ..."
- **`crowd_5db` / `kn_03`** (kn): `beneficiary_id` (mismatch: exp='1057', got='1507'); `limb_abnormality` (mismatch: exp={'present': False, 'location': None}, got={'present': True, 'location': 'unspecified'}); `danger_signs` (hallucinated: exp=[], got=['pus_umbilicus']); `risk_flags` (exp=['cord_infection', 'fever', 'jaundice'], got=['cord_infection', 'danger_sign:pus_umbilicus', 'fever', 'jaundice', 'limb_abnormality']); `validation_flags` (exp=[], got=[('beneficiary_id', 'unknown_beneficiary')]); `followup` (unnecessary follow-up (llm_ambiguity: ['limb_abnormality.location'])) — transcript: "ಫಲಾನುಭವಿ 1507. ತಾಯಿ 2.6 kg, ತಾಪಮಾನ 100.4 Fahrenheit. ಕೇವಲ ತಾಯಿ ಹಾಲು ಕುಡಿಯುತ್ತಿದೆ. ಹೊಕ್ಕ..."
