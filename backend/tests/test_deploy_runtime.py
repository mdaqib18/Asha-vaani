from __future__ import annotations

import logging
from pathlib import Path

from fastapi.testclient import TestClient
from sqlalchemy import func, select

from app.core.security import PiiRedactingFilter
from app.core.settings import Settings, get_settings
from app.db.models import Beneficiary
from app.db.repository import create_db_engine, make_session_factory
from app.db.store import VisitStore
from app.main import app


def test_health_returns_ok_without_db_warmup(tmp_path: Path) -> None:
    db_url = f"sqlite:///{(tmp_path / 'health.db').as_posix()}"
    app.dependency_overrides[get_settings] = lambda: Settings(
        DATABASE_URL=db_url,
        SEED_DEMO_DATA=False,
    )
    try:
        with TestClient(app) as client:
            res = client.get("/v1/health")
            assert res.status_code == 200
            assert res.json() == {"status": "ok"}
    finally:
        app.dependency_overrides.clear()


def test_sqlite_enables_wal_and_busy_timeout(tmp_path: Path) -> None:
    db_url = f"sqlite:///{(tmp_path / 'wal.db').as_posix()}"
    store = VisitStore(db_url)
    try:
        mode = store._conn.execute("PRAGMA journal_mode").fetchone()[0]
        timeout_ms = store._conn.execute("PRAGMA busy_timeout").fetchone()[0]
        assert str(mode).lower() == "wal"
        assert int(timeout_ms) >= 5000
    finally:
        store.close()

    engine = create_db_engine(db_url)
    try:
        with engine.connect() as conn:
            mode = conn.exec_driver_sql("PRAGMA journal_mode").scalar_one()
            timeout_ms = conn.exec_driver_sql("PRAGMA busy_timeout").scalar_one()
            fk = conn.exec_driver_sql("PRAGMA foreign_keys").scalar_one()
            assert str(mode).lower() == "wal"
            assert int(timeout_ms) >= 5000
            assert int(fk) == 1
    finally:
        engine.dispose()


def test_lifespan_seeds_labeled_demo_data_only_when_empty_and_enabled(tmp_path: Path) -> None:
    db_url = f"sqlite:///{(tmp_path / 'seed.db').as_posix()}"
    app.dependency_overrides[get_settings] = lambda: Settings(
        DATABASE_URL=db_url,
        SEED_DEMO_DATA=True,
    )
    try:
        with TestClient(app) as client:
            res = client.get("/v1/health")
            assert res.status_code == 200
    finally:
        app.dependency_overrides.clear()

    engine = create_db_engine(db_url)
    try:
        with make_session_factory(engine)() as db:
            demo_rows = db.execute(
                select(Beneficiary.id, Beneficiary.full_name).where(
                    Beneficiary.id.like("demo_seed_%")
                )
            ).all()
            assert len(demo_rows) == 6
            assert all(name.startswith("Demo ") for _, name in demo_rows)
    finally:
        engine.dispose()

    # Disabled flag on another fresh DB leaves beneficiaries empty
    db_url_off = f"sqlite:///{(tmp_path / 'noseed.db').as_posix()}"
    app.dependency_overrides[get_settings] = lambda: Settings(
        DATABASE_URL=db_url_off,
        SEED_DEMO_DATA=False,
    )
    try:
        with TestClient(app) as client:
            assert client.get("/v1/health").status_code == 200
    finally:
        app.dependency_overrides.clear()

    engine_off = create_db_engine(db_url_off)
    try:
        with make_session_factory(engine_off)() as db:
            assert (db.scalar(select(func.count()).select_from(Beneficiary)) or 0) == 0
    finally:
        engine_off.dispose()


def test_pii_filter_redacts_audio_paths() -> None:
    filt = PiiRedactingFilter()
    rec = logging.LogRecord(
        name="uvicorn.error",
        level=logging.INFO,
        pathname=__file__,
        lineno=1,
        msg='upload audio_path=/tmp/visit_123.wav file_path=offline/clip.mp3 "audio_path":"/var/data/a.wav" clip_42.m4a',
        args=(),
        exc_info=None,
    )
    assert filt.filter(rec) is True
    rendered = rec.getMessage()
    assert "visit_123.wav" not in rendered
    assert "clip.mp3" not in rendered
    assert "/var/data/a.wav" not in rendered
    assert "clip_42.m4a" not in rendered
    assert "[REDACTED]" in rendered or "[AUDIO_PATH_REDACTED]" in rendered
