from __future__ import annotations

import json
from dataclasses import dataclass
from datetime import date, datetime, timedelta, timezone
from typing import Iterable

from sqlalchemy import select

from app.core.config_loader import list_visit_configs
from app.db.models import Beneficiary, FollowupRecord, Visit
from app.db.repository import V2Repository
from app.db.store import StoredSession, VisitStore

VALID_PERIODS = ("today", "7d", "30d")

_RISK_RANK = {"high": 0, "watch": 1, "medium": 1, "low": 2, "none": 3}

_DEFAULT_PURPOSE_LABELS = {
    "newborn_home_visit": "Newborn home visit",
    "anc_visit": "Antenatal check (ANC)",
    "general_illness": "General illness",
    "ncd_screening": "BP & Sugar check (NCD)",
}


@dataclass(slots=True)
class NormalizedVisitRecord:
    """Unified visit projection across V2 SQLAlchemy tables and legacy VisitStore."""

    visit_id: str
    client_id: str | None
    beneficiary_id: str | None
    visit_type_code: str
    visited_date: date | None
    confirmed: bool
    risk_flags: list[str]
    referral_suggested: bool
    input_method: str
    duration_seconds: float | None
    has_followup: bool
    is_demo: bool


def resolve_period_bounds(
    period: str,
    *,
    today: date | None = None,
) -> tuple[str, date, date]:
    """Resolve `today`, `7d`, or `30d` into inclusive `(period, start_date, end_date)`."""
    normalized = (period or "7d").strip().lower()
    if normalized not in VALID_PERIODS:
        raise ValueError(f"Unsupported stats period '{period}'. Expected one of {VALID_PERIODS}.")
    end_date = today or datetime.now(timezone.utc).date()
    days = 1 if normalized == "today" else (7 if normalized == "7d" else 30)
    start_date = end_date - timedelta(days=days - 1)
    return normalized, start_date, end_date


def _parse_iso_date(raw: str | None) -> date | None:
    if not raw or not raw.strip():
        return None
    text = raw.strip()[:10]
    try:
        return date.fromisoformat(text)
    except ValueError:
        return None


def _parse_iso_datetime(raw: str | None) -> datetime | None:
    if not raw or not raw.strip():
        return None
    text = raw.strip()
    if text.endswith("Z"):
        text = text[:-1] + "+00:00"
    try:
        parsed = datetime.fromisoformat(text)
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed


def _measure_duration_seconds(started_raw: str | None, confirmed_raw: str | None) -> float | None:
    started = _parse_iso_datetime(started_raw)
    confirmed = _parse_iso_datetime(confirmed_raw)
    if started is None or confirmed is None:
        return None
    seconds = (confirmed - started).total_seconds()
    if seconds < 0 or seconds > 3600:
        return None
    return seconds


def _safe_json_list(raw: str | None) -> list[str]:
    if not raw:
        return []
    try:
        parsed = json.loads(raw)
    except json.JSONDecodeError:
        return []
    if not isinstance(parsed, list):
        return []
    return [str(item) for item in parsed if str(item).strip()]


def _humanize_key(key: str) -> str:
    cleaned = key.strip().replace("-", "_")
    return " ".join(part.capitalize() for part in cleaned.split("_") if part) or key


def _purpose_label_map() -> dict[str, str]:
    labels = dict(_DEFAULT_PURPOSE_LABELS)
    for cfg in list_visit_configs():
        name_en = cfg.name.get("en")
        if name_en:
            labels[cfg.effective_code] = name_en
    return labels


def _collect_visits(
    worker_id: str,
    repo: V2Repository,
    *,
    store: VisitStore | None = None,
    code_to_beneficiary_id: dict[str, str] | None = None,
) -> list[NormalizedVisitRecord]:
    """Load and deduplicate visits from V2 tables and optional legacy VisitStore."""
    collected: list[NormalizedVisitRecord] = []
    seen_ids: set[str] = set()

    with repo._session_factory() as db:
        visit_rows = list(
            db.scalars(select(Visit).where(Visit.worker_id == worker_id)).all()
        )
        visit_ids = [v.id for v in visit_rows]
        followup_visit_ids: set[str] = set()
        if visit_ids:
            followup_visit_ids = set(
                db.scalars(
                    select(FollowupRecord.visit_id).where(FollowupRecord.visit_id.in_(visit_ids))
                ).all()
            )

    for row in visit_rows:
        seen_ids.add(row.id)
        if row.client_id:
            seen_ids.add(row.client_id)
        v_date = (
            _parse_iso_date(row.visited_at)
            or _parse_iso_date(row.confirmed_at)
            or _parse_iso_date(row.updated_at)
        )
        confirmed = row.status in ("confirmed", "amended")
        flags = _safe_json_list(row.risk_flags_json)
        input_method = (row.input_method or "voice").strip().lower()
        duration = (
            _measure_duration_seconds(row.started_at, row.confirmed_at)
            if confirmed and input_method == "voice"
            else None
        )
        is_demo = (row.client_id or "").startswith("demo_seed_") or row.id.startswith("demo_seed_")
        collected.append(
            NormalizedVisitRecord(
                visit_id=row.id,
                client_id=row.client_id,
                beneficiary_id=row.beneficiary_id,
                visit_type_code=row.visit_type_code or "newborn_home_visit",
                visited_date=v_date,
                confirmed=confirmed,
                risk_flags=flags,
                referral_suggested=bool(row.referral_suggested),
                input_method=input_method,
                duration_seconds=duration,
                has_followup=row.id in followup_visit_ids,
                is_demo=is_demo,
            )
        )

    if store is not None:
        sessions: Iterable[StoredSession] = store.list_visits(asha_id=worker_id, saved_only=True)
        for sess in sessions:
            sess_vid = sess.visit_id or sess.session_id
            if sess_vid in seen_ids or sess.session_id in seen_ids:
                continue
            seen_ids.add(sess_vid)
            ben_ref = sess.record.beneficiary_id.value if sess.record.beneficiary_id else None
            resolved_ben_id = (
                code_to_beneficiary_id.get(str(ben_ref), str(ben_ref))
                if ben_ref and code_to_beneficiary_id
                else (str(ben_ref) if ben_ref else None)
            )
            v_date = _parse_iso_date(sess.updated_at) or _parse_iso_date(sess.created_at)
            flags = [str(f) for f in (sess.record.risk_flags or []) if str(f).strip()]
            v_type = (
                "newborn_home_visit" if sess.visit_type == "newborn" else sess.visit_type
            )
            duration = _measure_duration_seconds(sess.created_at, sess.updated_at)
            collected.append(
                NormalizedVisitRecord(
                    visit_id=sess_vid,
                    client_id=None,
                    beneficiary_id=resolved_ben_id,
                    visit_type_code=v_type,
                    visited_date=v_date,
                    confirmed=True,
                    risk_flags=flags,
                    referral_suggested=bool(flags),
                    input_method="voice",
                    duration_seconds=duration,
                    has_followup=sess.followup_count > 0,
                    is_demo=sess_vid.startswith("demo_seed_"),
                )
            )

    return collected


def _filter_confirmed_in_range(
    visits: list[NormalizedVisitRecord],
    start_date: date,
    end_date: date,
) -> list[NormalizedVisitRecord]:
    return [
        v
        for v in visits
        if v.confirmed and v.visited_date is not None and start_date <= v.visited_date <= end_date
    ]


def _beneficiary_is_demo(ben: Beneficiary) -> bool:
    return ben.id.startswith("demo_seed_") or ben.local_code.startswith("D-")


def compute_summary(
    *,
    worker_id: str,
    period: str,
    repo: V2Repository,
    store: VisitStore | None = None,
    today: date | None = None,
) -> dict:
    """Compute SPEC_V2 §6.1 summary metrics for a worker and period."""
    ref_today = today or datetime.now(timezone.utc).date()
    norm_period, start_date, end_date = resolve_period_bounds(period, today=ref_today)

    beneficiaries = repo.list_beneficiaries(worker_id)
    code_to_id = {b.local_code: b.id for b in beneficiaries}
    active_ids = {b.id for b in beneficiaries}

    due_today = 0
    overdue = 0
    high_risk_open = 0
    has_demo_data = any(_beneficiary_is_demo(b) for b in beneficiaries)

    for b in beneficiaries:
        if b.risk_level == "high":
            high_risk_open += 1
        due = _parse_iso_date(b.next_due_at)
        if due is None:
            continue
        if due < ref_today:
            overdue += 1
        elif due == ref_today:
            due_today += 1

    visits = _collect_visits(
        worker_id,
        repo,
        store=store,
        code_to_beneficiary_id=code_to_id,
    )
    if any(v.is_demo for v in visits):
        has_demo_data = True

    period_visits = _filter_confirmed_in_range(visits, start_date, end_date)
    visits_done = len(period_visits)
    referrals_suggested = sum(1 for v in period_visits if v.referral_suggested)

    durations = [v.duration_seconds for v in period_visits if v.duration_seconds is not None]
    avg_record_seconds = round(sum(durations) / len(durations), 1) if durations else None

    if visits_done > 0:
        voice_count = sum(1 for v in period_visits if v.input_method in ("voice", "mixed"))
        followup_count = sum(1 for v in period_visits if v.has_followup)
        voice_share = round(voice_count / visits_done, 4)
        followup_rate = round(followup_count / visits_done, 4)
    else:
        voice_share = None
        followup_rate = None

    cov_start = ref_today - timedelta(days=29)
    visited_last_30d = {
        v.beneficiary_id
        for v in _filter_confirmed_in_range(visits, cov_start, ref_today)
        if v.beneficiary_id in active_ids
    }
    active_count = len(beneficiaries)
    coverage = round(len(visited_last_30d) / active_count, 4) if active_count > 0 else 0.0

    return {
        "period": norm_period,
        "start_date": start_date.isoformat(),
        "end_date": end_date.isoformat(),
        "visits_done": visits_done,
        "due_today": due_today,
        "overdue": overdue,
        "active_beneficiaries": active_count,
        "coverage": coverage,
        "high_risk_open": high_risk_open,
        "referrals_suggested": referrals_suggested,
        "avg_record_seconds": avg_record_seconds,
        "voice_share": voice_share,
        "followup_rate": followup_rate,
        "has_demo_data": has_demo_data,
    }


def compute_visits_timeseries(
    *,
    worker_id: str,
    period: str,
    repo: V2Repository,
    store: VisitStore | None = None,
    today: date | None = None,
) -> list[dict]:
    """Return daily confirmed visit counts and high-risk visit counts over the window."""
    ref_today = today or datetime.now(timezone.utc).date()
    _, start_date, end_date = resolve_period_bounds(period, today=ref_today)
    beneficiaries = repo.list_beneficiaries(worker_id)
    visits = _collect_visits(
        worker_id,
        repo,
        store=store,
        code_to_beneficiary_id={b.local_code: b.id for b in beneficiaries},
    )
    period_visits = _filter_confirmed_in_range(visits, start_date, end_date)

    by_day: dict[str, dict[str, int]] = {}
    cur = start_date
    while cur <= end_date:
        by_day[cur.isoformat()] = {"count": 0, "high_risk_count": 0}
        cur += timedelta(days=1)

    for v in period_visits:
        assert v.visited_date is not None
        iso = v.visited_date.isoformat()
        bucket = by_day.get(iso)
        if bucket is None:
            continue
        bucket["count"] += 1
        if v.referral_suggested or len(v.risk_flags) > 0:
            bucket["high_risk_count"] += 1

    return [
        {
            "date": day_iso,
            "count": counts["count"],
            "high_risk_count": counts["high_risk_count"],
        }
        for day_iso, counts in by_day.items()
    ]


def compute_by_purpose(
    *,
    worker_id: str,
    period: str,
    repo: V2Repository,
    store: VisitStore | None = None,
    today: date | None = None,
) -> list[dict]:
    """Return confirmed visits grouped by `visit_type_code` in descending count order."""
    ref_today = today or datetime.now(timezone.utc).date()
    _, start_date, end_date = resolve_period_bounds(period, today=ref_today)
    beneficiaries = repo.list_beneficiaries(worker_id)
    visits = _collect_visits(
        worker_id,
        repo,
        store=store,
        code_to_beneficiary_id={b.local_code: b.id for b in beneficiaries},
    )
    period_visits = _filter_confirmed_in_range(visits, start_date, end_date)
    total = len(period_visits)
    if total == 0:
        return []

    counts: dict[str, int] = {}
    for v in period_visits:
        counts[v.visit_type_code] = counts.get(v.visit_type_code, 0) + 1

    labels = _purpose_label_map()
    rows = [
        {
            "key": code,
            "label": labels.get(code, _humanize_key(code)),
            "count": count,
            "share": round(count / total, 4),
        }
        for code, count in counts.items()
    ]
    rows.sort(key=lambda item: (-item["count"], item["key"]))
    return rows


def compute_risk_breakdown(
    *,
    worker_id: str,
    period: str,
    repo: V2Repository,
    store: VisitStore | None = None,
    today: date | None = None,
) -> list[dict]:
    """Return distinct risk flags observed on confirmed visits in the period."""
    ref_today = today or datetime.now(timezone.utc).date()
    _, start_date, end_date = resolve_period_bounds(period, today=ref_today)
    beneficiaries = repo.list_beneficiaries(worker_id)
    visits = _collect_visits(
        worker_id,
        repo,
        store=store,
        code_to_beneficiary_id={b.local_code: b.id for b in beneficiaries},
    )
    period_visits = _filter_confirmed_in_range(visits, start_date, end_date)

    counts: dict[str, int] = {}
    for v in period_visits:
        for flag in dict.fromkeys(v.risk_flags):
            counts[flag] = counts.get(flag, 0) + 1

    total_flags = sum(counts.values())
    if total_flags == 0:
        return []

    rows = [
        {
            "key": flag,
            "label": _humanize_key(flag),
            "count": count,
            "share": round(count / total_flags, 4),
        }
        for flag, count in counts.items()
    ]
    rows.sort(key=lambda item: (-item["count"], item["key"]))
    return rows


def compute_due_list(
    *,
    worker_id: str,
    repo: V2Repository,
    today: date | None = None,
    limit: int = 25,
) -> list[dict]:
    """Return overdue and due-today active beneficiaries ordered by urgency."""
    ref_today = today or datetime.now(timezone.utc).date()
    beneficiaries = repo.list_beneficiaries(worker_id)
    due_rows: list[tuple[tuple[int, int, str, str], dict]] = []

    for ben in beneficiaries:
        due = _parse_iso_date(ben.next_due_at)
        if due is None or due > ref_today:
            continue
        days_overdue = (ref_today - due).days
        risk_rank = _RISK_RANK.get(ben.risk_level, 3)
        sort_key = (-days_overdue, risk_rank, due.isoformat(), ben.local_code)
        due_rows.append(
            (
                sort_key,
                {
                    "beneficiary_id": ben.id,
                    "local_code": ben.local_code,
                    "full_name": ben.full_name,
                    "beneficiary_type": ben.beneficiary_type,
                    "next_due_at": due.isoformat(),
                    "days_overdue": days_overdue,
                    "risk_level": ben.risk_level,
                    "last_visit_at": ben.last_visit_at,
                },
            )
        )

    due_rows.sort(key=lambda item: item[0])
    return [item[1] for item in due_rows[: max(1, limit)]]
