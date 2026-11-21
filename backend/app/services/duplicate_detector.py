"""Transliteration-tolerant duplicate beneficiary detection (SPEC_V2 §5.4)."""

from __future__ import annotations

import re
import unicodedata
from dataclasses import dataclass
from datetime import date

_HONORIFICS: frozenset[str] = frozenset(
    {
        "smt",
        "shrimati",
        "shri",
        "sri",
        "mrs",
        "mr",
        "ms",
        "miss",
        "km",
        "kumari",
        "devi",
        "bai",
        "begum",
        "bibi",
        "w/o",
        "d/o",
        "s/o",
        "c/o",
        "श्रीमती",
        "श्री",
        "कुमारी",
        "देवी",
    }
)

_PHONETIC_RULES: tuple[tuple[str, str], ...] = (
    ("ee", "i"),
    ("oo", "u"),
    ("aa", "a"),
    ("ph", "f"),
    ("sh", "s"),
    ("kh", "k"),
    ("gh", "g"),
    ("bh", "b"),
    ("dh", "d"),
    ("th", "t"),
    ("jh", "j"),
    ("ch", "c"),
    ("v", "w"),
    ("z", "j"),
)


@dataclass(frozen=True)
class DuplicateCandidateInput:
    """Comparable record used for candidate duplicate screening."""

    id: str
    local_code: str
    full_name: str
    worker_id: str
    area_id: str | None = None
    dob: str | None = None
    phone_enc: str | None = None
    status: str = "active"
    deleted_at: str | None = None


@dataclass(frozen=True)
class DuplicateMatch:
    """Scored candidate duplicate with human-readable match reasons (never auto-merged)."""

    beneficiary_id: str
    local_code: str
    full_name: str
    dob: str | None
    score: float
    reasons: tuple[str, ...]


def _fold_phonetic(token: str) -> str:
    folded = token
    for src, dst in _PHONETIC_RULES:
        folded = folded.replace(src, dst)
    # Collapse consecutive duplicate characters (e.g. 'sunnita' -> 'sunita')
    out: list[str] = []
    for ch in folded:
        if not out or out[-1] != ch:
            out.append(ch)
    return "".join(out)


def normalize_name(name: str) -> str:
    """Normalize name: lowercase, strip honorifics/punctuation, fold phonetic spelling."""
    text = unicodedata.normalize("NFKC", name or "").lower().strip()
    text = re.sub(r"[./_-]+", " ", text)
    raw_tokens = re.findall(r"[^\W\d_]+", text, flags=re.UNICODE)
    cleaned: list[str] = []
    for token in raw_tokens:
        if token in _HONORIFICS:
            continue
        cleaned.append(_fold_phonetic(token))
    if not cleaned and raw_tokens:
        cleaned = [_fold_phonetic(t) for t in raw_tokens]
    return " ".join(cleaned)


def normalize_phone(phone: str | None) -> str:
    """Normalize phone number to trailing 10 digits."""
    if not phone:
        return ""
    digits = re.sub(r"\D", "", phone)
    return digits[-10:] if len(digits) > 10 else digits


def levenshtein_distance(a: str, b: str) -> int:
    """Compute Levenshtein edit distance in pure Python."""
    if a == b:
        return 0
    if not a:
        return len(b)
    if not b:
        return len(a)
    prev = list(range(len(b) + 1))
    for i, ca in enumerate(a, start=1):
        curr = [i]
        for j, cb in enumerate(b, start=1):
            cost = 0 if ca == cb else 1
            curr.append(min(curr[j - 1] + 1, prev[j] + 1, prev[j - 1] + cost))
        prev = curr
    return prev[-1]


def name_similarity(a: str, b: str) -> float:
    """Compute normalized token-order-tolerant name similarity in [0.0, 1.0]."""
    na = normalize_name(a)
    nb = normalize_name(b)
    if not na or not nb:
        return 0.0

    compact_a = na.replace(" ", "")
    compact_b = nb.replace(" ", "")
    sorted_a = "".join(sorted(na.split()))
    sorted_b = "".join(sorted(nb.split()))

    def _ratio(s1: str, s2: str) -> float:
        denom = max(len(s1), len(s2))
        if denom == 0:
            return 0.0
        return 1.0 - (levenshtein_distance(s1, s2) / denom)

    return max(_ratio(compact_a, compact_b), _ratio(sorted_a, sorted_b))


def _parse_iso_date(raw: str | None) -> date | None:
    if not raw:
        return None
    try:
        return date.fromisoformat(raw[:10])
    except ValueError:
        return None


def find_duplicate_candidates(
    candidate: DuplicateCandidateInput,
    existing: list[DuplicateCandidateInput],
    *,
    name_threshold: float = 0.78,
    dob_window_days: int = 366,
) -> list[DuplicateMatch]:
    """Find potential active duplicates in the same area; never auto-merges."""
    cand_phone = normalize_phone(candidate.phone_enc)
    cand_dob = _parse_iso_date(candidate.dob)
    matches: list[DuplicateMatch] = []

    for row in existing:
        if row.id == candidate.id:
            continue
        if row.status != "active" or row.deleted_at is not None:
            continue
        if candidate.area_id and row.area_id and candidate.area_id != row.area_id:
            continue
        if not (candidate.area_id and row.area_id) and candidate.worker_id != row.worker_id:
            continue

        sim = name_similarity(candidate.full_name, row.full_name)
        row_phone = normalize_phone(row.phone_enc)
        phone_match = bool(cand_phone and row_phone and len(cand_phone) >= 7 and cand_phone == row_phone)

        row_dob = _parse_iso_date(row.dob)
        dob_known_both = cand_dob is not None and row_dob is not None
        dob_close = dob_known_both and abs((cand_dob - row_dob).days) <= dob_window_days

        reasons: list[str] = []
        is_match = False

        # Match when:
        # 1) Fuzzy name similarity holds AND (DOB within ~1 yr OR same phone OR DOB unknown with high name match)
        # 2) Exact phone match AND DOB is close (handles spelling differences with shared phone+DOB)
        if sim >= name_threshold and (dob_close or phone_match or (not dob_known_both and sim >= 0.88)):
            is_match = True
            reasons.append("similar_name")
        elif phone_match and dob_close and sim >= 0.50:
            is_match = True
            reasons.append("similar_name")

        if phone_match:
            reasons.append("same_phone")
        if dob_close:
            reasons.append("dob_within_1y")

        if is_match:
            score = round(min(1.0, max(sim, 0.92 if phone_match else sim)), 3)
            matches.append(
                DuplicateMatch(
                    beneficiary_id=row.id,
                    local_code=row.local_code,
                    full_name=row.full_name,
                    dob=row.dob,
                    score=score,
                    reasons=tuple(dict.fromkeys(reasons)),
                )
            )

    matches.sort(key=lambda m: (-m.score, m.local_code))
    return matches
