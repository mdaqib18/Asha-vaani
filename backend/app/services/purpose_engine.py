"""Registry-driven purpose suggestion, speech keyword detection, and safe AST rule evaluation."""

from __future__ import annotations

import ast
import re
from dataclasses import dataclass
from datetime import date

from app.core.config_loader import VisitTypeConfig, list_visit_configs, load_visit_config
from app.services.due_engine import NEWBORN_SCHEDULE_DAYS


@dataclass(frozen=True)
class DetectedPurpose:
    """Purpose matched from spoken phrase or text hint."""

    code: str
    confidence: float
    matched_keyword: str


@dataclass(frozen=True)
class PurposeSuggestion:
    """Suggested visit purpose plus localized clinical reason and alternative valid codes."""

    suggested_code: str
    reason: dict[str, str]
    other_codes: list[str]
    detected_purpose: DetectedPurpose | None = None


_ALLOWED_COMPARE_OPS = (ast.Lt, ast.LtE, ast.Gt, ast.GtE, ast.Eq, ast.NotEq)


def _unwrap_value(raw: object) -> object:
    if isinstance(raw, dict) and "value" in raw:
        return raw.get("value")
    return raw


def _eval_rule_ast(node: ast.AST, env: dict[str, object]) -> bool:
    if isinstance(node, ast.Expression):
        return _eval_rule_ast(node.body, env)

    if isinstance(node, ast.BoolOp):
        if isinstance(node.op, ast.And):
            return all(_eval_rule_ast(v, env) for v in node.values)
        if isinstance(node.op, ast.Or):
            return any(_eval_rule_ast(v, env) for v in node.values)
        raise ValueError(f"Unsupported boolean op: {type(node.op).__name__}")

    if isinstance(node, ast.UnaryOp):
        if isinstance(node.op, ast.Not):
            return not _eval_rule_ast(node.operand, env)
        raise ValueError(f"Unsupported unary op: {type(node.op).__name__}")

    if isinstance(node, ast.Compare):
        left = _eval_rule_value(node.left, env)
        if left is None:
            return False
        curr_left = left
        for op, comparator in zip(node.ops, node.comparators):
            if not isinstance(op, _ALLOWED_COMPARE_OPS):
                raise ValueError(f"Unsupported comparison op: {type(op).__name__}")
            right = _eval_rule_value(comparator, env)
            if right is None:
                return False
            if isinstance(op, (ast.Lt, ast.LtE, ast.Gt, ast.GtE)):
                if isinstance(curr_left, bool) or isinstance(right, bool):
                    return False
                try:
                    lnum = float(curr_left)
                    rnum = float(right)
                except (TypeError, ValueError):
                    return False
                ok = (
                    (lnum < rnum)
                    if isinstance(op, ast.Lt)
                    else (lnum <= rnum)
                    if isinstance(op, ast.LtE)
                    else (lnum > rnum)
                    if isinstance(op, ast.Gt)
                    else (lnum >= rnum)
                )
            elif isinstance(op, ast.Eq):
                ok = curr_left == right
            else:
                ok = curr_left != right
            if not ok:
                return False
            curr_left = right
        return True

    val = _eval_rule_value(node, env)
    return bool(val)


def _eval_rule_value(node: ast.AST, env: dict[str, object]) -> object:
    if isinstance(node, ast.Name):
        # Support YAML lowercase booleans `true`/`false` cleanly.
        if node.id == "true":
            return True
        if node.id == "false":
            return False
        if node.id == "null":
            return None
        return env.get(node.id)
    if isinstance(node, ast.Constant):
        if isinstance(node.value, (int, float, str, bool)) or node.value is None:
            return node.value
        raise ValueError(f"Disallowed constant type: {type(node.value).__name__}")
    raise ValueError(f"Disallowed AST expression node: {type(node).__name__}")


def eval_safe_expression(expr: str, env: dict[str, object]) -> bool:
    """Safely evaluate a constrained boolean comparison expression via AST whitelist."""
    tree = ast.parse(expr, mode="eval")
    return _eval_rule_ast(tree, env)


def evaluate_yaml_risk_rules(
    payload: dict[str, object],
    config: VisitTypeConfig,
) -> tuple[list[str], bool]:
    """Evaluate YAML declarative `risk_rules` safely against a structured payload."""
    env: dict[str, object] = {}
    for key, raw in payload.items():
        val = _unwrap_value(raw)
        if (
            isinstance(val, (int, float))
            and not isinstance(val, bool)
            and key in config.ranges
        ):
            bounds = config.ranges[key]
            if val < bounds.min or val > bounds.max:
                val = None  # Out-of-range values are untrusted and skipped by rules.
        env[key] = val

    flags: list[str] = []
    severities: dict[str, str] = {}

    def add_flag(name: str, severity: str = "high") -> None:
        if name not in flags:
            flags.append(name)
        severities[name] = severity

    for rule in config.risk_rules:
        if eval_safe_expression(rule.when, env):
            add_flag(rule.flag, rule.severity)

    danger = env.get("danger_signs")
    if isinstance(danger, list) and len(danger) > 0:
        add_flag("danger_signs_present", "high")

    high_risk = set(config.high_risk_flags)
    referral_suggested = any(
        (severities.get(flag) == "high" or flag in high_risk or flag.split(":", 1)[0] in high_risk)
        for flag in flags
    )
    return flags, referral_suggested


def detect_purpose_from_text(
    text: str,
    *,
    configs: list[VisitTypeConfig] | None = None,
) -> DetectedPurpose | None:
    """Detect a visit purpose from spoken/typed text using registered YAML voice_keywords."""
    normalized = re.sub(r"\s+", " ", (text or "").strip().lower())
    if not normalized:
        return None

    candidates: list[tuple[int, str, str]] = []
    for cfg in configs if configs is not None else list_visit_configs(active_only=True):
        code = cfg.effective_code
        for kw in cfg.voice_keywords:
            clean_kw = re.sub(r"\s+", " ", kw.strip().lower())
            if not clean_kw:
                continue
            if _keyword_matches(normalized, clean_kw):
                candidates.append((len(clean_kw), code, kw))

    if not candidates:
        return None
    # Prefer the longest (most specific) matched keyword phrase.
    candidates.sort(key=lambda item: item[0], reverse=True)
    _, best_code, best_kw = candidates[0]
    return DetectedPurpose(code=best_code, confidence=0.9, matched_keyword=best_kw)


def _keyword_matches(normalized_text: str, kw: str) -> bool:
    if kw.isascii() and kw.replace(" ", "").isalnum():
        pattern = r"(?<!\w)" + re.escape(kw) + r"(?!\w)"
        return re.search(pattern, normalized_text) is not None
    return kw in normalized_text


def _next_hbnc_day(dob: date, ref_today: date) -> int | None:
    age_days = max(0, (ref_today - dob).days)
    for d in NEWBORN_SCHEDULE_DAYS:
        if d >= age_days:
            return d
    return None


def suggest_visit_purpose(
    *,
    beneficiary_type: str = "newborn",
    dob: date | None = None,
    last_visit_at: date | None = None,
    next_due_at: date | None = None,
    spoken_hint: str | None = None,
    today: date | None = None,
    configs: list[VisitTypeConfig] | None = None,
) -> PurposeSuggestion:
    """Suggest the best visit purpose for a beneficiary, plus alternative valid purposes."""
    all_configs = configs if configs is not None else list_visit_configs(active_only=True)
    available_codes = {c.effective_code for c in all_configs}
    ref_today = today or date.today()
    btype = (beneficiary_type or "newborn").strip().lower()

    suggested_code = "general_illness"
    reason = {
        "en": "General check or new symptoms reported",
        "hi": "सामान्य जांच या नए लक्षण दर्ज करें",
        "kn": "ಸಾಮಾನ್ಯ ತಪಾಸಣೆ ಅಥವಾ ಹೊಸ ಲಕ್ಷಣಗಳನ್ನು ದಾಖಲಿಸಿ",
    }

    if btype == "newborn":
        age_days = (ref_today - dob).days if dob is not None else None
        if age_days is None or age_days <= 42:
            if "newborn_home_visit" in available_codes:
                suggested_code = "newborn_home_visit"
                next_day = _next_hbnc_day(dob, ref_today) if dob is not None else None
                if next_day is not None:
                    reason = {
                        "en": f"Newborn day {next_day} visit is due",
                        "hi": f"नवजात दिन {next_day} भेंट बाकी है",
                        "kn": f"ನವಜಾತ ದಿನ {next_day} ಭೇಟಿ ಬಾಕಿ ಇದೆ",
                    }
                else:
                    reason = {
                        "en": "Newborn home visit is due",
                        "hi": "नवजात गृह भेंट बाकी है",
                        "kn": "ನವಜಾತ ಮನೆ ಭೇಟಿ ಬಾಕಿ ಇದೆ",
                    }
    elif btype == "pregnant_woman" and "anc_visit" in available_codes:
        suggested_code = "anc_visit"
        reason = {
            "en": "Antenatal check is due",
            "hi": "प्रसव पूर्व जांच (ANC) बाकी है",
            "kn": "ಗರ್ಭಿಣಿ ತಪಾಸಣೆ (ANC) ಬಾಕಿ ಇದೆ",
        }
    elif btype in ("adult", "other") and "ncd_screening" in available_codes:
        suggested_code = "ncd_screening"
        reason = {
            "en": "Routine BP and blood sugar screening",
            "hi": "नियमित बीपी और ब्लड शुगर जांच",
            "kn": "ನಿಯಮಿತ ಬಿಪಿ ಮತ್ತು ಸಕ್ಕರೆ ತಪಾಸಣೆ",
        }

    # Include matching active purposes first, preserving registry order without duplicates.
    matching_others: list[str] = []
    for cfg in all_configs:
        code = cfg.effective_code
        if code == suggested_code:
            continue
        if not cfg.applies_to or btype in cfg.applies_to:
            matching_others.append(code)
    # Also ensure general_illness is always reachable if registered.
    if (
        "general_illness" in available_codes
        and suggested_code != "general_illness"
        and "general_illness" not in matching_others
    ):
        matching_others.append("general_illness")

    detected = detect_purpose_from_text(spoken_hint or "", configs=all_configs)
    if detected is not None and detected.code == suggested_code:
        # Already the primary suggestion; keep confirmation banner clear if identical?
        # Keep detected intact so callers can see spoken match too.
        pass

    return PurposeSuggestion(
        suggested_code=suggested_code,
        reason=reason,
        other_codes=matching_others,
        detected_purpose=detected,
    )


def get_schema_version(visit_type: str) -> int:
    """Return active schema_version for a visit type code."""
    return load_visit_config(visit_type).schema_version
