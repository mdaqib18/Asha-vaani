"""Deterministic normalization for spoken numbers, weights, temperatures, and IDs."""

from __future__ import annotations

import re

# Map Devanagari (०-९) and Kannada (೦-೯) digits to ASCII 0-9.
_DIGIT_TRANSLATION = str.maketrans(
    "०१२३४५६७८९೦೧೨೩೪೫೬೭೮೯",
    "01234567890123456789",
)

_FILLER_WORDS: set[str] = {
    "hai",
    "haan",
    "ji",
    "aur",
    "umm",
    "uh",
    "ah",
    "ok",
    "okay",
    "the",
    "is",
    "and",
    "of",
    "ka",
    "ki",
    "ke",
    "ko",
    "se",
    "me",
    "mein",
    "a",
    "an",
    "है",
    "हाँ",
    "जी",
    "और",
    "का",
    "की",
    "के",
    "में",
    "से",
    "ಮತ್ತು",
    "ಇದೆ",
    "ಹೌದು",
    "ಆಗಿದೆ",
}

_DIGIT_WORDS: dict[str, int] = {
    # English
    "zero": 0,
    "one": 1,
    "two": 2,
    "three": 3,
    "four": 4,
    "five": 5,
    "six": 6,
    "seven": 7,
    "eight": 8,
    "nine": 9,
    # Hindi (romanized + Devanagari)
    "shunya": 0,
    "sifar": 0,
    "ek": 1,
    "do": 2,
    "teen": 3,
    "tin": 3,
    "chaar": 4,
    "char": 4,
    "paanch": 5,
    "panch": 5,
    "chhe": 6,
    "chah": 6,
    "che": 6,
    "saat": 7,
    "sat": 7,
    "aath": 8,
    "ath": 8,
    "nau": 9,
    "शून्य": 0,
    "सिफर": 0,
    "एक": 1,
    "दो": 2,
    "तीन": 3,
    "चार": 4,
    "पाँच": 5,
    "पांच": 5,
    "छह": 6,
    "छे": 6,
    "सात": 7,
    "आठ": 8,
    "नौ": 9,
    # Kannada (romanized + Kannada script)
    "sonne": 0,
    "ondu": 1,
    "eradu": 2,
    "mooru": 3,
    "muru": 3,
    "naalku": 4,
    "nalku": 4,
    "aidu": 5,
    "aaru": 6,
    "aru": 6,
    "elu": 7,
    "entu": 8,
    "ombattu": 9,
    "ಸೊನ್ನೆ": 0,
    "ಒಂದು": 1,
    "ಎರಡು": 2,
    "ಮೂರು": 3,
    "ನಾಲ್ಕು": 4,
    "ಐದು": 5,
    "ಆರು": 6,
    "ಏಳು": 7,
    "ಎಂಟು": 8,
    "ಒಂಬತ್ತು": 9,
}

_WORD_NUMBERS: dict[str, int] = {
    **_DIGIT_WORDS,
    # English 10-90
    "ten": 10,
    "eleven": 11,
    "twelve": 12,
    "thirteen": 13,
    "fourteen": 14,
    "fifteen": 15,
    "sixteen": 16,
    "seventeen": 17,
    "eighteen": 18,
    "nineteen": 19,
    "twenty": 20,
    "thirty": 30,
    "forty": 40,
    "fifty": 50,
    "sixty": 60,
    "seventy": 70,
    "eighty": 80,
    "ninety": 90,
    # Hindi 10-99
    "das": 10,
    "दस": 10,
    "gyaarah": 11,
    "gyarah": 11,
    "ग्यारह": 11,
    "baarah": 12,
    "barah": 12,
    "बारह": 12,
    "terah": 13,
    "तेरह": 13,
    "chaudah": 14,
    "चौदह": 14,
    "pandrah": 15,
    "पंद्रह": 15,
    "solah": 16,
    "सोलह": 16,
    "satrah": 17,
    "सत्रह": 17,
    "atharah": 18,
    "अठारह": 18,
    "unnees": 19,
    "unnis": 19,
    "उन्नीस": 19,
    "bees": 20,
    "बीस": 20,
    "ikkees": 21,
    "इक्कीस": 21,
    "baais": 22,
    "बाईस": 22,
    "teis": 23,
    "तेईस": 23,
    "chaubees": 24,
    "चौबीस": 24,
    "pachchees": 25,
    "pachis": 25,
    "पच्चीस": 25,
    "chhabbees": 26,
    "छब्बीस": 26,
    "sattaais": 27,
    "सत्ताईस": 27,
    "atthaais": 28,
    "अट्ठाईस": 28,
    "untees": 29,
    "उनतीस": 29,
    "tees": 30,
    "तीस": 30,
    "ikattees": 31,
    "इकतीस": 31,
    "battees": 32,
    "बत्तीस": 32,
    "taintees": 33,
    "तैंतीस": 33,
    "chautees": 34,
    "चौंतीस": 34,
    "paintees": 35,
    "पैंतीस": 35,
    "chhattees": 36,
    "छत्तीस": 36,
    "saintees": 37,
    "सैंतीस": 37,
    "adtees": 38,
    "अड़तीस": 38,
    "untaalis": 39,
    "उनतालीस": 39,
    "chaalis": 40,
    "chalis": 40,
    "चालीस": 40,
    "iktaalis": 41,
    "इकतालीस": 41,
    "bayaalis": 42,
    "बयालीस": 42,
    "taintaalis": 43,
    "तैंतालीस": 43,
    "chauwaalis": 44,
    "चौवालीस": 44,
    "paintaalis": 45,
    "पैंतालीस": 45,
    "chhiyaalis": 46,
    "छियालीस": 46,
    "saintaalis": 47,
    "सैंतालीस": 47,
    "adtaalis": 48,
    "अड़तालीस": 48,
    "unchaas": 49,
    "उनचास": 49,
    "pachaas": 50,
    "pachas": 50,
    "पचास": 50,
    "ikyaawan": 51,
    "इक्यावन": 51,
    "baawan": 52,
    "बावन": 52,
    "tirepan": 53,
    "तिरेपन": 53,
    "chauwan": 54,
    "चौवन": 54,
    "pachpan": 55,
    "पचपन": 55,
    "chhappan": 56,
    "छप्पन": 56,
    "sattaawan": 57,
    "सत्तावन": 57,
    "atthaawan": 58,
    "अट्ठावन": 58,
    "unsath": 59,
    "उनसठ": 59,
    "saath": 60,
    "साठ": 60,
    "iksath": 61,
    "इकसठ": 61,
    "baasath": 62,
    "बासठ": 62,
    "tiresath": 63,
    "तिरेसठ": 63,
    "chausath": 64,
    "चौंसठ": 64,
    "painsath": 65,
    "पैंसठ": 65,
    "chhiyaasath": 66,
    "छियासठ": 66,
    "sadsath": 67,
    "सड़सठ": 67,
    "adsath": 68,
    "अड़सठ": 68,
    "unhattar": 69,
    "उनहत्तर": 69,
    "sattar": 70,
    "सत्तर": 70,
    "ikhattar": 71,
    "इकहत्तर": 71,
    "bahattar": 72,
    "बहत्तर": 72,
    "tihattar": 73,
    "तिहत्तर": 73,
    "chauhattar": 74,
    "चौहत्तर": 74,
    "pachhattar": 75,
    "पचहत्तर": 75,
    "chhihattar": 76,
    "छिहत्तर": 76,
    "satahattar": 77,
    "सतहत्तर": 77,
    "athahattar": 78,
    "अठहत्तर": 78,
    "unyaasi": 79,
    "उनासी": 79,
    "assi": 80,
    "अस्सी": 80,
    "ikyaasi": 81,
    "इक्यासी": 81,
    "bayaasi": 82,
    "बयासी": 82,
    "tiraasi": 83,
    "तिरासी": 83,
    "chauraasi": 84,
    "चौरासी": 84,
    "pachaasi": 85,
    "पचासी": 85,
    "chhiyaasi": 86,
    "छियासी": 86,
    "sataasi": 87,
    "सतासी": 87,
    "athaasi": 88,
    "अठासी": 88,
    "nawaasi": 89,
    "नवासी": 89,
    "nabbe": 90,
    "नब्बे": 90,
    "ikyaanwe": 91,
    "इक्यानवे": 91,
    "baanwe": 92,
    "बानवे": 92,
    "tiraanwe": 93,
    "तिरानवे": 93,
    "chauraanwe": 94,
    "चौरानवे": 94,
    "pachaanwe": 95,
    "पचानवे": 95,
    "chhiyaanwe": 96,
    "छियानवे": 96,
    "sattanve": 97,
    "सत्तानवे": 97,
    "atthanve": 98,
    "अट्ठानवे": 98,
    "अठानवे": 98,
    "ninyaanwe": 99,
    "ninyanve": 99,
    "निन्यानवे": 99,
    # Kannada 10-99 & common standalone hundreds
    "hattu": 10,
    "ಹತ್ತು": 10,
    "hannondu": 11,
    "ಹನ್ನೊಂದು": 11,
    "hanneradu": 12,
    "ಹನ್ನೆರಡು": 12,
    "hadimooru": 13,
    "ಹದಿಮೂರು": 13,
    "hadinaalku": 14,
    "ಹದಿನಾಲ್ಕು": 14,
    "hadinaidu": 15,
    "ಹದಿನೈದು": 15,
    "hadinaaru": 16,
    "ಹದಿನಾರು": 16,
    "hadinelu": 17,
    "ಹದಿನೇಳು": 17,
    "hadinentu": 18,
    "ಹದಿನೆಂಟು": 18,
    "hattombattu": 19,
    "ಹತ್ತೊಂಬತ್ತು": 19,
    "ippattu": 20,
    "ಇಪ್ಪತ್ತು": 20,
    "ippattaidu": 25,
    "ಇಪ್ಪತ್ತೈದು": 25,
    "moovattu": 30,
    "ಮೂವತ್ತು": 30,
    "ಮೂವತ್ತೈದು": 35,
    "ಮೂವತ್ತಾರು": 36,
    "ಮೂವತ್ತೇಳು": 37,
    "ಮೂವತ್ತೆಂಟು": 38,
    "ಮೂವತ್ತೊಂಬತ್ತು": 39,
    "nalavattu": 40,
    "ನಾಲ್ವತ್ತು": 40,
    "ನಾಲ್ವತ್ತೈದು": 45,
    "aivattu": 50,
    "ಐವತ್ತು": 50,
    "ಐವತ್ತೈದು": 55,
    "aravattu": 60,
    "ಅರವತ್ತು": 60,
    "ಅರವತ್ತೈದು": 65,
    "eppattu": 70,
    "ಎಪ್ಪತ್ತು": 70,
    "embattu": 80,
    "ಎಂಬತ್ತು": 80,
    "tombattu": 90,
    "ತೊಂಬತ್ತು": 90,
    "ತೊಂಬತ್ತೈದು": 95,
    "ತೊಂಬತ್ತಾರು": 96,
    "ತೊಂಬತ್ತೇಳು": 97,
    "ತೊಂಬತ್ತೆಂಟು": 98,
    "ತೊಂಬತ್ತೊಂಬತ್ತು": 99,
    "innooru": 200,
    "ಇನ್ನೂರು": 200,
    "munnooru": 300,
    "ಮುನ್ನೂರು": 300,
    "naanooru": 400,
    "ನಾಲ್ಕುನೂರು": 400,
    "ನಾನೂರು": 400,
    "ainooru": 500,
    "ಐನೂರು": 500,
    "aarunooru": 600,
    "ಆರುನೂರು": 600,
    "elunooru": 700,
    "ಏಳುನೂರು": 700,
    "entunooru": 800,
    "ಎಂಟುನೂರು": 800,
    "ombattunooru": 900,
    "ಒಂಬತ್ತುನೂರು": 900,
}

_MULTIPLIERS: dict[str, int] = {
    "hundred": 100,
    "sau": 100,
    "सौ": 100,
    "nooru": 100,
    "ನೂರು": 100,
    "noora": 100,
    "ನೂರ": 100,
    "thousand": 1000,
    "hazaar": 1000,
    "hazar": 1000,
    "हज़ार": 1000,
    "हजार": 1000,
    "saavira": 1000,
    "ಸಾವಿರ": 1000,
    "saavirada": 1000,
    "ಸಾವಿರದ": 1000,
}

_STANDALONE_FRACTIONS: dict[str, float] = {
    "dedh": 1.5,
    "डेढ़": 1.5,
    "dhai": 2.5,
    "dhaai": 2.5,
    "ढाई": 2.5,
    "aadha": 0.5,
    "aadhe": 0.5,
    "आधा": 0.5,
    "आधे": 0.5,
    "half": 0.5,
    "ardha": 0.5,
    "ಅರ್ಧ": 0.5,
    "paav": 0.25,
    "pao": 0.25,
    "पाव": 0.25,
    "paun": 0.75,
    "pauna": 0.75,
    "पौन": 0.75,
    "पौना": 0.75,
    # Common fused Kannada X + vare forms
    "onduvare": 1.5,
    "eraduvare": 2.5,
    "mooruvare": 3.5,
    "naalkuvare": 4.5,
    "aiduvare": 5.5,
    "ಒಂದೂವರೆ": 1.5,
    "ಎರಡುವರೆ": 2.5,
    "ಎರಡೂವರೆ": 2.5,
    "ಮೂರುವರೆ": 3.5,
    "ಮೂರೂವರೆ": 3.5,
    "ನಾಲ್ಕೂವರೆ": 4.5,
    "ಐದೂವರೆ": 5.5,
}

_PREFIX_FRACTIONS: dict[str, float] = {
    "sava": 0.25,
    "sawa": 0.25,
    "सवा": 0.25,
    "saadhe": 0.5,
    "sadhe": 0.5,
    "saade": 0.5,
    "साढ़े": 0.5,
    "साढे": 0.5,
    "साडे": 0.5,
    "paune": -0.25,
    "पौने": -0.25,
}

_POSTFIX_FRACTIONS: dict[str, float] = {
    "vare": 0.5,
    "uvare": 0.5,
    "ವರೆ": 0.5,
    "ೂವರೆ": 0.5,
    "kaalu": 0.25,
    "kaal": 0.25,
    "ಕಾಲು": 0.25,
    "mukkalu": 0.75,
    "ಮುಕ್ಕಾಲು": 0.75,
}

_DECIMAL_WORDS: set[str] = {
    "point",
    "dot",
    "dashamlav",
    "दशमलव",
    "पॉइंट",
    "ಪಾಯಿಂಟ್",
    "ಡಾಟ್",
}

_KG_UNITS: set[str] = {
    "kg",
    "kgs",
    "kilo",
    "kilos",
    "kilogram",
    "kilograms",
    "किलो",
    "किलोग्राम",
    "ಕೆಜಿ",
    "ಕಿಲೋ",
    "ಕಿಲೋಗ್ರಾಂ",
}

_GRAM_UNITS: set[str] = {
    "g",
    "gm",
    "gms",
    "gram",
    "grams",
    "ग्राम",
    "ಗ್ರಾಂ",
}

_FAHRENHEIT_UNITS: set[str] = {
    "f",
    "fahrenheit",
    "farenheit",
    "फारेनहाइट",
    "फ़ारेनहाइट",
    "फैरेनहाइट",
    "ಫ್ಯಾರನ್ಹೀಟ್",
    "ಫ್ಯಾರನ್\u200cಹೀಟ್",
}

_CELSIUS_UNITS: set[str] = {
    "c",
    "celsius",
    "centigrade",
    "सेल्सियस",
    "ಸೆಲ್ಸಿಯಸ್",
}

_DEGREE_WORDS: set[str] = {
    "degree",
    "degrees",
    "deg",
    "डिग्री",
    "ಡಿಗ್ರಿ",
}

_NUMERIC_RE = re.compile(r"^\d+(?:\.\d+)?$")
_PUNCT_STRIP_RE = re.compile(r"^[,?!;:'\"()।\-]+|[,?!;:'\"()।\-]+$")


def _preprocess(text: str, separate_units: bool = False) -> list[str]:
    """Lowercase, convert native digits, and split into clean tokens."""
    normalized = text.translate(_DIGIT_TRANSLATION).lower()
    normalized = normalized.replace("°", " ")
    normalized = normalized.replace("-", " ")
    if separate_units:
        normalized = re.sub(
            r"(\d)([a-z\u0900-\u097f\u0c80-\u0cff]+)",
            r"\1 \2",
            normalized,
        )
    tokens: list[str] = []
    for raw in normalized.split():
        cleaned = _PUNCT_STRIP_RE.sub("", raw)
        # Strip trailing dot only if it is sentence punctuation, not e.g. '2.5'
        if cleaned.endswith("."):
            cleaned = cleaned[:-1]
        if cleaned:
            tokens.append(cleaned)
    return tokens


def _is_number_token(tok: str) -> bool:
    return bool(
        _NUMERIC_RE.match(tok)
        or tok in _WORD_NUMBERS
        or tok in _MULTIPLIERS
        or tok in _STANDALONE_FRACTIONS
        or tok in _PREFIX_FRACTIONS
        or tok in _POSTFIX_FRACTIONS
    )


def _eval_integer_phrase(tokens: list[str]) -> float | None:
    """Evaluate a sequence of integer/multiplier/fraction tokens without decimal point."""
    if not tokens:
        return None

    # Handle single numeric literal directly
    if len(tokens) == 1 and _NUMERIC_RE.match(tokens[0]):
        return float(tokens[0])

    idx = 0
    prefix_adj: float | None = None
    if tokens[0] in _PREFIX_FRACTIONS:
        prefix_adj = _PREFIX_FRACTIONS[tokens[0]]
        idx = 1

    # Standalone prefix like "sava" alone -> 1.25
    if idx >= len(tokens):
        if prefix_adj is not None:
            return 1.0 + prefix_adj if prefix_adj >= 0 else 1.0 + prefix_adj
        return None

    # Standalone fraction word (e.g. "dhai", "dedh")
    if len(tokens) - idx == 1 and tokens[idx] in _STANDALONE_FRACTIONS:
        base = _STANDALONE_FRACTIONS[tokens[idx]]
        return base

    # Check postfix fraction at the end (e.g. "eradu vare")
    postfix_adj = 0.0
    end = len(tokens)
    if end - idx >= 2 and tokens[end - 1] in _POSTFIX_FRACTIONS:
        postfix_adj = _POSTFIX_FRACTIONS[tokens[end - 1]]
        end -= 1

    total = 0.0
    current = 0.0
    seen = False
    has_prefix_applied = False

    i = idx
    while i < end:
        tok = tokens[i]
        if _NUMERIC_RE.match(tok):
            val = float(tok)
            if prefix_adj is not None and not has_prefix_applied:
                val += prefix_adj
                has_prefix_applied = True
            current += val
            seen = True
        elif tok in _WORD_NUMBERS:
            val = float(_WORD_NUMBERS[tok])
            current += val
            seen = True
        elif tok in _MULTIPLIERS:
            mult = _MULTIPLIERS[tok]
            if current == 0.0:
                current = 1.0
            if prefix_adj is not None and not has_prefix_applied:
                current += prefix_adj
                has_prefix_applied = True
            current *= mult
            if mult >= 1000:
                total += current
                current = 0.0
            seen = True
        elif tok in _STANDALONE_FRACTIONS:
            current += _STANDALONE_FRACTIONS[tok]
            seen = True
        i += 1

    if not seen:
        return None

    result = total + current
    if prefix_adj is not None and not has_prefix_applied:
        result += prefix_adj
    result += postfix_adj
    return result


def parse_number(text: str) -> float | None:
    """Parse spoken or written numbers in English, Hindi, or Kannada to a float."""
    tokens = [t for t in _preprocess(text) if t not in _FILLER_WORDS]
    if not tokens:
        return None

    # Find the first contiguous span of number tokens (including decimal markers)
    start = None
    for i, tok in enumerate(tokens):
        if _is_number_token(tok) or (
            tok in _DECIMAL_WORDS
            and i + 1 < len(tokens)
            and _is_number_token(tokens[i + 1])
        ):
            start = i
            break
    if start is None:
        return None

    span: list[str] = []
    for i in range(start, len(tokens)):
        tok = tokens[i]
        if _is_number_token(tok):
            span.append(tok)
        elif tok in _DECIMAL_WORDS and i + 1 < len(tokens) and _is_number_token(tokens[i + 1]):
            span.append(tok)
        else:
            break

    # Split at first decimal marker if present
    dec_idx = next((i for i, t in enumerate(span) if t in _DECIMAL_WORDS), None)
    if dec_idx is None:
        return _eval_integer_phrase(span)

    int_tokens = span[:dec_idx]
    frac_tokens = span[dec_idx + 1 :]
    if not frac_tokens:
        return _eval_integer_phrase(int_tokens)

    int_val = _eval_integer_phrase(int_tokens) if int_tokens else 0.0
    if int_val is None:
        return None

    frac_parts: list[str] = []
    for ft in frac_tokens:
        if _NUMERIC_RE.match(ft) and "." not in ft:
            frac_parts.append(ft)
        elif ft in _WORD_NUMBERS:
            frac_parts.append(str(_WORD_NUMBERS[ft]))
        else:
            break
    if not frac_parts:
        return int_val

    frac_str = "".join(frac_parts)
    return float(f"{int(int_val)}.{frac_str}")


def parse_digit_sequence(text: str) -> str | None:
    """Extract a spoken or numeric ID digit sequence (e.g. 'ek zero chaar do' -> '1042')."""
    tokens = _preprocess(text)
    digits: list[str] = []
    for tok in tokens:
        if tok.isdigit():
            digits.append(tok)
        elif tok in _DIGIT_WORDS:
            digits.append(str(_DIGIT_WORDS[tok]))
    return "".join(digits) if digits else None


def parse_weight_kg(text: str) -> float | None:
    """Parse spoken weight with kg/gram units into kilograms as a float."""
    tokens = [t for t in _preprocess(text, separate_units=True) if t not in _FILLER_WORDS]
    if not tokens:
        return None

    total_kg = 0.0
    seen_unit = False
    parsed_any = False
    buf: list[str] = []

    for tok in tokens:
        if tok in _KG_UNITS:
            seen_unit = True
            val = parse_number(" ".join(buf))
            if val is not None:
                total_kg += val
                parsed_any = True
            buf.clear()
        elif tok in _GRAM_UNITS:
            seen_unit = True
            val = parse_number(" ".join(buf))
            if val is not None:
                total_kg += val / 1000.0
                parsed_any = True
            buf.clear()
        else:
            buf.append(tok)

    if seen_unit:
        return round(total_kg, 4) if parsed_any else None

    return parse_number(text)


def parse_temperature_c(text: str) -> tuple[float, bool] | None:
    """Parse spoken temperature into (celsius, converted_from_fahrenheit)."""
    tokens = [t for t in _preprocess(text, separate_units=True) if t not in _FILLER_WORDS]
    if not tokens:
        return None

    is_fahrenheit = any(t in _FAHRENHEIT_UNITS for t in tokens)
    filtered = [
        t
        for t in tokens
        if t not in _FAHRENHEIT_UNITS and t not in _CELSIUS_UNITS and t not in _DEGREE_WORDS
    ]
    val = parse_number(" ".join(filtered))
    if val is None:
        return None

    if is_fahrenheit:
        celsius = round((val - 32.0) * 5.0 / 9.0, 1)
        return (celsius, True)

    return (round(val, 1), False)
