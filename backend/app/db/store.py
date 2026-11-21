"""SQLite persistence layer for visit sessions, generated TTS audio, and sync idempotency."""

from __future__ import annotations

import json
import sqlite3
import threading
import uuid
from datetime import datetime, timezone
from functools import lru_cache
from pathlib import Path

from pydantic import BaseModel, Field

from app.core.settings import get_settings
from app.schemas.newborn_visit import Flag, NewbornVisitRecord
from app.services.extractor import Ambiguity

_BACKEND_DIR = Path(__file__).resolve().parent.parent.parent


class StoredSession(BaseModel):
    """Persisted multi-turn visit session state."""

    session_id: str
    visit_id: str | None = None
    asha_id: str = "asha_001"
    visit_type: str = "newborn_home_visit"
    language: str = "hi"
    status: str = "draft"
    record: NewbornVisitRecord = Field(default_factory=NewbornVisitRecord)
    flags: list[Flag] = Field(default_factory=list)
    ambiguities: list[Ambiguity] = Field(default_factory=list)
    asked_fields: list[str] = Field(default_factory=list)
    followup_count: int = 0
    last_transcript: str = ""
    created_at: str = ""
    updated_at: str = ""


def _utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _resolve_sqlite_target(database_url: str) -> str:
    if database_url == "sqlite:///:memory:" or database_url == ":memory:":
        return ":memory:"
    raw = database_url
    if raw.startswith("sqlite:///"):
        raw = raw[len("sqlite:///") :]
    path = Path(raw)
    if not path.is_absolute():
        path = (_BACKEND_DIR / path).resolve()
    path.parent.mkdir(parents=True, exist_ok=True)
    return str(path)


class VisitStore:
    """Thread-safe SQLite store for visits, audio clips, and sync results."""

    def __init__(self, database_url: str) -> None:
        self.database_url = database_url
        self._v2_engine: object | None = None
        self._v2_repo: object | None = None
        target = _resolve_sqlite_target(database_url)
        self._conn = sqlite3.connect(target, check_same_thread=False)
        self._conn.row_factory = sqlite3.Row
        self._lock = threading.Lock()
        self.init_db()

    def init_db(self) -> None:
        with self._lock:
            self._conn.executescript(
                """
                CREATE TABLE IF NOT EXISTS visit_sessions (
                    session_id TEXT PRIMARY KEY,
                    visit_id TEXT,
                    asha_id TEXT NOT NULL,
                    visit_type TEXT NOT NULL,
                    language TEXT NOT NULL,
                    status TEXT NOT NULL,
                    record_json TEXT NOT NULL,
                    flags_json TEXT NOT NULL,
                    ambiguities_json TEXT NOT NULL,
                    asked_fields_json TEXT NOT NULL,
                    followup_count INTEGER NOT NULL,
                    last_transcript TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS audio_clips (
                    audio_id TEXT PRIMARY KEY,
                    content_type TEXT NOT NULL,
                    data BLOB NOT NULL,
                    created_at TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS sync_items (
                    client_id TEXT PRIMARY KEY,
                    response_json TEXT NOT NULL,
                    created_at TEXT NOT NULL
                );
                """
            )
            self._conn.commit()

    def close(self) -> None:
        with self._lock:
            self._conn.close()
        if self._v2_engine is not None and hasattr(self._v2_engine, "dispose"):
            self._v2_engine.dispose()
            self._v2_engine = None
            self._v2_repo = None

    def _row_to_session(self, row: sqlite3.Row) -> StoredSession:
        return StoredSession(
            session_id=row["session_id"],
            visit_id=row["visit_id"],
            asha_id=row["asha_id"],
            visit_type=row["visit_type"],
            language=row["language"],
            status=row["status"],
            record=NewbornVisitRecord.model_validate_json(row["record_json"]),
            flags=[Flag.model_validate(item) for item in json.loads(row["flags_json"])],
            ambiguities=[
                Ambiguity.model_validate(item) for item in json.loads(row["ambiguities_json"])
            ],
            asked_fields=json.loads(row["asked_fields_json"]),
            followup_count=row["followup_count"],
            last_transcript=row["last_transcript"],
            created_at=row["created_at"],
            updated_at=row["updated_at"],
        )

    def create_or_update_session(self, session: StoredSession) -> StoredSession:
        now = _utc_now_iso()
        if not session.created_at:
            session.created_at = now
        session.updated_at = now

        with self._lock:
            self._conn.execute(
                """
                INSERT INTO visit_sessions (
                    session_id, visit_id, asha_id, visit_type, language, status,
                    record_json, flags_json, ambiguities_json, asked_fields_json,
                    followup_count, last_transcript, created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(session_id) DO UPDATE SET
                    visit_id = excluded.visit_id,
                    asha_id = excluded.asha_id,
                    visit_type = excluded.visit_type,
                    language = excluded.language,
                    status = excluded.status,
                    record_json = excluded.record_json,
                    flags_json = excluded.flags_json,
                    ambiguities_json = excluded.ambiguities_json,
                    asked_fields_json = excluded.asked_fields_json,
                    followup_count = excluded.followup_count,
                    last_transcript = excluded.last_transcript,
                    updated_at = excluded.updated_at
                """,
                (
                    session.session_id,
                    session.visit_id,
                    session.asha_id,
                    session.visit_type,
                    session.language,
                    session.status,
                    session.record.model_dump_json(),
                    json.dumps([f.model_dump(mode="json") for f in session.flags]),
                    json.dumps([a.model_dump(mode="json") for a in session.ambiguities]),
                    json.dumps(session.asked_fields),
                    session.followup_count,
                    session.last_transcript,
                    session.created_at,
                    session.updated_at,
                ),
            )
            self._conn.commit()
        return session

    def get_session(self, session_id: str) -> StoredSession | None:
        with self._lock:
            row = self._conn.execute(
                "SELECT * FROM visit_sessions WHERE session_id = ?",
                (session_id,),
            ).fetchone()
        return self._row_to_session(row) if row is not None else None

    def list_visits(
        self,
        asha_id: str | None = None,
        saved_only: bool = True,
    ) -> list[StoredSession]:
        clauses: list[str] = []
        params: list[object] = []
        if asha_id is not None:
            clauses.append("asha_id = ?")
            params.append(asha_id)
        if saved_only:
            clauses.append("status = 'saved'")
        where = f"WHERE {' AND '.join(clauses)}" if clauses else ""
        sql = f"SELECT * FROM visit_sessions {where} ORDER BY updated_at DESC"
        with self._lock:
            rows = self._conn.execute(sql, params).fetchall()
        return [self._row_to_session(r) for r in rows]

    def save_audio(self, data: bytes, content_type: str = "audio/mpeg") -> str:
        audio_id = str(uuid.uuid4())
        with self._lock:
            self._conn.execute(
                "INSERT INTO audio_clips (audio_id, content_type, data, created_at) VALUES (?, ?, ?, ?)",
                (audio_id, content_type, data, _utc_now_iso()),
            )
            self._conn.commit()
        return audio_id

    def get_audio(self, audio_id: str) -> tuple[bytes, str] | None:
        with self._lock:
            row = self._conn.execute(
                "SELECT data, content_type FROM audio_clips WHERE audio_id = ?",
                (audio_id,),
            ).fetchone()
        if row is None:
            return None
        return bytes(row["data"]), str(row["content_type"])

    def get_sync_result(self, client_id: str) -> dict | None:
        with self._lock:
            row = self._conn.execute(
                "SELECT response_json FROM sync_items WHERE client_id = ?",
                (client_id,),
            ).fetchone()
        return json.loads(row["response_json"]) if row is not None else None

    def save_sync_result(self, client_id: str, response: dict) -> None:
        with self._lock:
            self._conn.execute(
                """
                INSERT INTO sync_items (client_id, response_json, created_at)
                VALUES (?, ?, ?)
                ON CONFLICT(client_id) DO NOTHING
                """,
                (client_id, json.dumps(response), _utc_now_iso()),
            )
            self._conn.commit()


@lru_cache(maxsize=1)
def get_store() -> VisitStore:
    """FastAPI dependency returning the singleton VisitStore."""
    return VisitStore(get_settings().DATABASE_URL)
