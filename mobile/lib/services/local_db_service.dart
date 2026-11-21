import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/beneficiary.dart';
import '../models/newborn_visit.dart';

class QueuedAudioItem {
  const QueuedAudioItem({
    required this.clientId,
    required this.ashaId,
    required this.beneficiaryId,
    required this.beneficiaryLabel,
    required this.audioPath,
    required this.language,
    this.visitType = 'newborn_home_visit',
    this.status = 'pending',
    required this.recordedAt,
    this.lastError,
  });

  final String clientId;
  final String ashaId;
  final String beneficiaryId;
  final String beneficiaryLabel;
  final String audioPath;
  final String language;
  final String visitType;
  final String status;
  final String recordedAt;
  final String? lastError;

  factory QueuedAudioItem.fromRow(Map<String, Object?> row) {
    return QueuedAudioItem(
      clientId: row['client_id'] as String? ?? '',
      ashaId: row['asha_id'] as String? ?? '',
      beneficiaryId: row['beneficiary_id'] as String? ?? '',
      beneficiaryLabel: row['beneficiary_label'] as String? ?? '',
      audioPath: row['audio_path'] as String? ?? '',
      language: row['language'] as String? ?? 'hi',
      visitType: row['visit_type'] as String? ?? 'newborn_home_visit',
      status: row['status'] as String? ?? 'pending',
      recordedAt: row['recorded_at'] as String? ?? '',
      lastError: row['last_error'] as String?,
    );
  }
}

class LocalDraft {
  const LocalDraft({
    required this.sessionId,
    required this.clientId,
    required this.ashaId,
    required this.beneficiaryId,
    required this.turn,
    required this.status,
    required this.updatedAt,
  });

  final String sessionId;
  final String clientId;
  final String ashaId;
  final String beneficiaryId;
  final VisitTurnResponse turn;
  final String status;
  final String updatedAt;

  factory LocalDraft.fromRow(Map<String, Object?> row) {
    final decoded = jsonDecode(row['turn_json'] as String) as Map<String, dynamic>;
    return LocalDraft(
      sessionId: row['session_id'] as String? ?? '',
      clientId: row['client_id'] as String? ?? '',
      ashaId: row['asha_id'] as String? ?? '',
      beneficiaryId: row['beneficiary_id'] as String? ?? '',
      turn: VisitTurnResponse.fromJson(decoded),
      status: row['status'] as String? ?? 'ready_to_review',
      updatedAt: row['updated_at'] as String? ?? '',
    );
  }
}

abstract class LocalDbService {
  Future<void> cacheBeneficiaries(String ashaId, List<Beneficiary> items);
  Future<List<Beneficiary>> getCachedBeneficiaries(String ashaId);

  Future<void> enqueueAudio(QueuedAudioItem item);
  Future<List<QueuedAudioItem>> getPendingQueue({String? ashaId});
  Future<void> markQueueSynced(String clientId);
  Future<void> markQueueError(
    String clientId,
    String message, {
    bool permanent = false,
  });

  Future<void> saveDraft(LocalDraft draft);
  Future<List<LocalDraft>> getDrafts({String? ashaId});
  Future<void> deleteDraft(String sessionId);

  Future<void> cacheVisits(String ashaId, List<VisitSummary> visits);
  Future<List<VisitSummary>> getCachedVisits(String ashaId);
}

class SqfliteLocalDbService implements LocalDbService {
  Database? _db;

  Future<Database> _open() async {
    if (_db != null && _db!.isOpen) return _db!;
    final dbDir = await getDatabasesPath();
    final dbPath = p.join(dbDir, 'ashavaani_local.db');
    _db = await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE beneficiaries (
            asha_id TEXT NOT NULL,
            id TEXT NOT NULL,
            label TEXT NOT NULL,
            PRIMARY KEY (asha_id, id)
          )
        ''');
        await db.execute('''
          CREATE TABLE drafts (
            session_id TEXT PRIMARY KEY,
            client_id TEXT,
            asha_id TEXT NOT NULL,
            beneficiary_id TEXT,
            turn_json TEXT NOT NULL,
            status TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE queue (
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
        ''');
        await db.execute('''
          CREATE TABLE visits (
            session_id TEXT PRIMARY KEY,
            visit_id TEXT,
            asha_id TEXT NOT NULL,
            summary_json TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');
      },
    );
    return _db!;
  }

  @override
  Future<void> cacheBeneficiaries(String ashaId, List<Beneficiary> items) async {
    final db = await _open();
    await db.transaction((txn) async {
      await txn.delete('beneficiaries', where: 'asha_id = ?', whereArgs: [ashaId]);
      for (final item in items) {
        await txn.insert(
          'beneficiaries',
          {'asha_id': ashaId, 'id': item.id, 'label': item.label},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  @override
  Future<List<Beneficiary>> getCachedBeneficiaries(String ashaId) async {
    final db = await _open();
    final rows = await db.query(
      'beneficiaries',
      where: 'asha_id = ?',
      whereArgs: [ashaId],
      orderBy: 'id ASC',
    );
    return rows
        .map(
          (r) => Beneficiary(
            id: r['id'] as String? ?? '',
            label: r['label'] as String? ?? '',
          ),
        )
        .toList();
  }

  @override
  Future<void> enqueueAudio(QueuedAudioItem item) async {
    final db = await _open();
    await db.insert(
      'queue',
      {
        'client_id': item.clientId,
        'asha_id': item.ashaId,
        'beneficiary_id': item.beneficiaryId,
        'beneficiary_label': item.beneficiaryLabel,
        'audio_path': item.audioPath,
        'language': item.language,
        'visit_type': item.visitType,
        'status': item.status,
        'recorded_at': item.recordedAt,
        'last_error': item.lastError,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<List<QueuedAudioItem>> getPendingQueue({String? ashaId}) async {
    final db = await _open();
    final where = ashaId != null
        ? "status = 'pending' AND asha_id = ?"
        : "status = 'pending'";
    final args = ashaId != null ? [ashaId] : null;
    final rows = await db.query(
      'queue',
      where: where,
      whereArgs: args,
      orderBy: 'recorded_at DESC',
    );
    return rows.map(QueuedAudioItem.fromRow).toList();
  }

  @override
  Future<void> markQueueSynced(String clientId) async {
    final db = await _open();
    await db.update(
      'queue',
      {'status': 'synced', 'last_error': null},
      where: 'client_id = ?',
      whereArgs: [clientId],
    );
  }

  @override
  Future<void> markQueueError(
    String clientId,
    String message, {
    bool permanent = false,
  }) async {
    final db = await _open();
    await db.update(
      'queue',
      {
        'status': permanent ? 'error_permanent' : 'pending',
        'last_error': message,
      },
      where: 'client_id = ?',
      whereArgs: [clientId],
    );
  }

  @override
  Future<void> saveDraft(LocalDraft draft) async {
    final db = await _open();
    await db.insert(
      'drafts',
      {
        'session_id': draft.sessionId,
        'client_id': draft.clientId,
        'asha_id': draft.ashaId,
        'beneficiary_id': draft.beneficiaryId,
        'turn_json': jsonEncode(draft.turn.toJson()),
        'status': draft.status,
        'updated_at': draft.updatedAt,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<List<LocalDraft>> getDrafts({String? ashaId}) async {
    final db = await _open();
    final rows = await db.query(
      'drafts',
      where: ashaId != null ? 'asha_id = ?' : null,
      whereArgs: ashaId != null ? [ashaId] : null,
      orderBy: 'updated_at DESC',
    );
    return rows.map(LocalDraft.fromRow).toList();
  }

  @override
  Future<void> deleteDraft(String sessionId) async {
    final db = await _open();
    await db.delete('drafts', where: 'session_id = ?', whereArgs: [sessionId]);
  }

  @override
  Future<void> cacheVisits(String ashaId, List<VisitSummary> visits) async {
    final db = await _open();
    await db.transaction((txn) async {
      await txn.delete('visits', where: 'asha_id = ?', whereArgs: [ashaId]);
      for (final v in visits) {
        await txn.insert(
          'visits',
          {
            'session_id': v.sessionId,
            'visit_id': v.visitId,
            'asha_id': ashaId,
            'summary_json': jsonEncode(v.toJson()),
            'updated_at': v.updatedAt,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  @override
  Future<List<VisitSummary>> getCachedVisits(String ashaId) async {
    final db = await _open();
    final rows = await db.query(
      'visits',
      where: 'asha_id = ?',
      whereArgs: [ashaId],
      orderBy: 'updated_at DESC',
    );
    return rows.map((r) {
      final decoded =
          jsonDecode(r['summary_json'] as String) as Map<String, dynamic>;
      return VisitSummary.fromJson(decoded);
    }).toList();
  }
}
