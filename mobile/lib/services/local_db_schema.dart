import 'package:sqflite/sqflite.dart';

import 'due_engine.dart';

const int kLocalDbVersion = 2;

/// Declarative V2 SQLite schema and v1 -> v2 migration SQL (SPEC_V2 §5.1, §5.2).
class LocalDbSchema {
  LocalDbSchema._();

  static const List<String> v2TableNames = [
    'workers',
    'areas',
    'households',
    'beneficiaries',
    'pregnancies',
    'visit_types',
    'visits',
    'visit_measurements',
    'visit_amendments',
    'followups',
    'audio_assets',
    'consents',
    'sync_queue',
    'audit_log',
  ];

  static const List<String> v2IndexNames = [
    'ix_beneficiaries_worker_status_due',
    'uq_beneficiaries_worker_local_code',
    'ix_visits_beneficiary_visited',
    'ix_visits_worker_visited',
    'ix_visit_measurements_ben_key_at',
  ];

  static const List<String> createTableStatements = [
    '''
    CREATE TABLE IF NOT EXISTS workers (
      id TEXT PRIMARY KEY,
      worker_code TEXT NOT NULL UNIQUE,
      name TEXT NOT NULL,
      language_pref TEXT NOT NULL DEFAULT 'hi',
      area_ids TEXT NOT NULL DEFAULT '[]',
      pin_hash TEXT NOT NULL DEFAULT '',
      created_at TEXT NOT NULL
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS areas (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      code TEXT NOT NULL UNIQUE
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS households (
      id TEXT PRIMARY KEY,
      area_id TEXT NOT NULL,
      note TEXT NOT NULL DEFAULT '',
      created_at TEXT NOT NULL
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS visit_types (
      code TEXT PRIMARY KEY,
      schema_version INTEGER NOT NULL DEFAULT 1,
      name_i18n TEXT NOT NULL DEFAULT '{}',
      active INTEGER NOT NULL DEFAULT 1
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS beneficiaries (
      id TEXT PRIMARY KEY,
      local_code TEXT NOT NULL,
      external_id TEXT,
      worker_id TEXT NOT NULL,
      area_id TEXT,
      household_id TEXT,
      full_name TEXT NOT NULL,
      sex TEXT NOT NULL DEFAULT 'unknown',
      dob TEXT,
      dob_is_estimated INTEGER NOT NULL DEFAULT 0,
      beneficiary_type TEXT NOT NULL DEFAULT 'newborn',
      mother_id TEXT,
      phone_enc TEXT,
      consent_id TEXT,
      status TEXT NOT NULL DEFAULT 'active',
      risk_level TEXT NOT NULL DEFAULT 'none',
      last_visit_at TEXT,
      next_due_at TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      deleted_at TEXT,
      version INTEGER NOT NULL DEFAULT 1
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS pregnancies (
      id TEXT PRIMARY KEY,
      beneficiary_id TEXT NOT NULL,
      lmp_date TEXT,
      edd_date TEXT,
      gravida INTEGER,
      parity INTEGER,
      outcome TEXT,
      status TEXT NOT NULL DEFAULT 'active',
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS visits (
      id TEXT PRIMARY KEY,
      client_id TEXT UNIQUE,
      beneficiary_id TEXT,
      worker_id TEXT NOT NULL,
      visit_type_code TEXT NOT NULL DEFAULT 'newborn_home_visit',
      schema_version INTEGER NOT NULL DEFAULT 1,
      visited_at TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'draft',
      payload_json TEXT NOT NULL DEFAULT '{}',
      risk_flags_json TEXT NOT NULL DEFAULT '[]',
      referral_suggested INTEGER NOT NULL DEFAULT 0,
      next_due_at TEXT,
      transcript_text TEXT NOT NULL DEFAULT '',
      language TEXT NOT NULL DEFAULT 'hi',
      input_method TEXT NOT NULL DEFAULT 'voice',
      started_at TEXT,
      confirmed_at TEXT,
      updated_at TEXT NOT NULL,
      version INTEGER NOT NULL DEFAULT 1
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS visit_measurements (
      id TEXT PRIMARY KEY,
      visit_id TEXT NOT NULL,
      beneficiary_id TEXT,
      key TEXT NOT NULL,
      value_num REAL NOT NULL,
      unit TEXT NOT NULL DEFAULT '',
      measured_at TEXT NOT NULL
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS visit_amendments (
      id TEXT PRIMARY KEY,
      visit_id TEXT NOT NULL,
      changed_by TEXT NOT NULL,
      changes_json TEXT NOT NULL,
      reason TEXT NOT NULL DEFAULT '',
      created_at TEXT NOT NULL
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS followups (
      id TEXT PRIMARY KEY,
      visit_id TEXT NOT NULL,
      question_text TEXT NOT NULL,
      target_fields TEXT NOT NULL DEFAULT '[]',
      answer_text TEXT NOT NULL DEFAULT '',
      created_at TEXT NOT NULL
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS audio_assets (
      id TEXT PRIMARY KEY,
      visit_id TEXT,
      path TEXT NOT NULL,
      duration_ms INTEGER NOT NULL DEFAULT 0,
      state TEXT NOT NULL DEFAULT 'local',
      delete_after TEXT,
      created_at TEXT NOT NULL
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS consents (
      id TEXT PRIMARY KEY,
      beneficiary_id TEXT NOT NULL,
      kind TEXT NOT NULL DEFAULT 'beneficiary_registration',
      given_by TEXT NOT NULL DEFAULT 'self',
      method TEXT NOT NULL DEFAULT 'verbal',
      policy_version TEXT NOT NULL DEFAULT 'v2_2026_01',
      given_at TEXT NOT NULL
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS sync_queue (
      id TEXT PRIMARY KEY,
      entity TEXT NOT NULL,
      entity_id TEXT NOT NULL,
      op TEXT NOT NULL,
      attempts INTEGER NOT NULL DEFAULT 0,
      last_error TEXT,
      created_at TEXT NOT NULL
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS audit_log (
      id TEXT PRIMARY KEY,
      actor_id TEXT NOT NULL,
      action TEXT NOT NULL,
      entity TEXT NOT NULL,
      entity_id TEXT NOT NULL,
      device_id TEXT NOT NULL DEFAULT 'mobile',
      at TEXT NOT NULL
    )
    ''',
    // V1 compatibility tables preserved across upgrades
    '''
    CREATE TABLE IF NOT EXISTS drafts (
      session_id TEXT PRIMARY KEY,
      client_id TEXT,
      asha_id TEXT NOT NULL,
      beneficiary_id TEXT,
      turn_json TEXT NOT NULL,
      status TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS queue (
      client_id TEXT PRIMARY KEY,
      asha_id TEXT NOT NULL,
      beneficiary_id TEXT NOT NULL,
      beneficiary_label TEXT NOT NULL,
      audio_path TEXT NOT NULL,
      language TEXT NOT NULL,
      visit_type TEXT NOT NULL,
      status TEXT NOT NULL,
      recorded_at TEXT NOT NULL,
      last_error TEXT
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS cached_visit_summaries (
      session_id TEXT PRIMARY KEY,
      visit_id TEXT,
      asha_id TEXT NOT NULL,
      summary_json TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
    ''',
  ];

  static const List<String> createIndexStatements = [
    '''
    CREATE INDEX IF NOT EXISTS ix_beneficiaries_worker_status_due
      ON beneficiaries (worker_id, status, next_due_at)
    ''',
    '''
    CREATE UNIQUE INDEX IF NOT EXISTS uq_beneficiaries_worker_local_code
      ON beneficiaries (worker_id, local_code)
    ''',
    '''
    CREATE INDEX IF NOT EXISTS ix_visits_beneficiary_visited
      ON visits (beneficiary_id, visited_at DESC)
    ''',
    '''
    CREATE INDEX IF NOT EXISTS ix_visits_worker_visited
      ON visits (worker_id, visited_at)
    ''',
    '''
    CREATE INDEX IF NOT EXISTS ix_visit_measurements_ben_key_at
      ON visit_measurements (beneficiary_id, key, measured_at)
    ''',
  ];

  static Future<void> createV2(DatabaseExecutor db) async {
    for (final stmt in createTableStatements) {
      await db.execute(stmt);
    }
    for (final idx in createIndexStatements) {
      await db.execute(idx);
    }
  }

  static Future<void> upgradeV1ToV2(
    DatabaseExecutor db, {
    DateTime? now,
  }) async {
    final ts = (now ?? DateTime.now().toUtc()).toIso8601String();
    final today = DueEngine.formatIsoDate(now ?? DateTime.now());

    // Preserve V1 rows under temporary/compat table names before creating V2 tables.
    await db.execute('ALTER TABLE beneficiaries RENAME TO beneficiaries_v1_legacy');
    await db.execute('ALTER TABLE visits RENAME TO cached_visit_summaries');

    await createV2(db);

    await db.execute(
      '''
      INSERT OR IGNORE INTO beneficiaries (
        id, local_code, worker_id, full_name, sex, dob_is_estimated,
        beneficiary_type, status, risk_level, next_due_at, created_at, updated_at, version
      )
      SELECT
        'legacy_' || asha_id || '_' || id,
        id,
        asha_id,
        label,
        'unknown',
        0,
        'newborn',
        'active',
        'none',
        ?,
        ?,
        ?,
        1
      FROM beneficiaries_v1_legacy
      ''',
      [today, ts, ts],
    );
    await db.execute('DROP TABLE IF EXISTS beneficiaries_v1_legacy');
  }
}
