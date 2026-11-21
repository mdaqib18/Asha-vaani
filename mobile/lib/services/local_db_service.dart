import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/beneficiary.dart';
import '../models/newborn_visit.dart';
import '../models/v2_models.dart';
import 'due_engine.dart';
import 'local_db_schema.dart';

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
  // V1 compatibility methods
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

  // V2 structured data layer methods (SPEC_V2 §5)
  Future<BeneficiaryRecord> upsertBeneficiaryV2(
    BeneficiaryRecord record, {
    PregnancyRecord? pregnancy,
    ConsentRecord? consent,
    String? actorId,
  });
  Future<List<BeneficiaryRecord>> getBeneficiariesV2(
    String workerId, {
    bool includeDeleted = false,
  });
  Future<BeneficiaryRecord?> getBeneficiaryV2(String beneficiaryId);
  Future<void> softDeleteBeneficiaryV2(
    String beneficiaryId, {
    required String actorId,
  });

  Future<void> saveConsent(ConsentRecord consent);
  Future<List<ConsentRecord>> getConsentsForBeneficiary(String beneficiaryId);

  Future<VisitRecord> confirmVisitV2(
    VisitRecord visit, {
    int? intervalDays,
    DateTime? dob,
    DateTime? lmpDate,
    String? actorId,
  });
  Future<(VisitRecord, VisitAmendment)> amendVisitV2({
    required String visitId,
    required String changedBy,
    required Map<String, dynamic> changes,
    required String reason,
    List<String>? riskFlags,
    bool? referralSuggested,
  });
  Future<List<VisitRecord>> getVisitsV2({String? workerId, String? beneficiaryId});
  Future<List<VisitAmendment>> getVisitAmendments(String visitId);
  Future<List<VisitMeasurement>> getVisitMeasurements(
    String beneficiaryId, {
    String? key,
  });
  Future<List<AuditLogEntry>> getAuditLogs({String? entityId});

  Future<void> enqueueSyncV2(SyncQueueEntry entry);
  Future<List<SyncQueueEntry>> getSyncQueueV2();
  Future<void> markSyncAttemptV2(String id, {String? error});
  Future<void> removeSyncItemV2(String id);

  Future<void> saveAudioAsset(AudioAssetRecord asset);
  Future<List<String>> purgeExpiredAudioAssets({
    DateTime? now,
    Future<void> Function(String path)? deleteFile,
  });
}

class SqfliteLocalDbService implements LocalDbService {
  Database? _db;

  Future<Database> _open() async {
    if (_db != null && _db!.isOpen) return _db!;
    final dbDir = await getDatabasesPath();
    final dbPath = p.join(dbDir, 'ashavaani_local.db');
    _db = await openDatabase(
      dbPath,
      version: kLocalDbVersion,
      onCreate: (db, version) async {
        await LocalDbSchema.createV2(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await LocalDbSchema.upgradeV1ToV2(db);
        }
      },
    );
    return _db!;
  }

  @override
  Future<void> cacheBeneficiaries(String ashaId, List<Beneficiary> items) async {
    final db = await _open();
    final now = DateTime.now().toUtc().toIso8601String();
    await db.transaction((txn) async {
      await txn.delete(
        'beneficiaries',
        where: "worker_id = ? AND id LIKE 'legacy_%'",
        whereArgs: [ashaId],
      );
      for (final item in items) {
        final existing = await txn.query(
          'beneficiaries',
          where: 'worker_id = ? AND local_code = ?',
          whereArgs: [ashaId, item.id],
          limit: 1,
        );
        if (existing.isNotEmpty) {
          await txn.update(
            'beneficiaries',
            {'full_name': item.label, 'updated_at': now},
            where: 'id = ?',
            whereArgs: [existing.first['id']],
          );
        } else {
          await txn.insert(
            'beneficiaries',
            BeneficiaryRecord(
              id: 'legacy_${ashaId}_${item.id}',
              localCode: item.id,
              workerId: ashaId,
              fullName: item.label,
              beneficiaryType: 'newborn',
              createdAt: now,
              updatedAt: now,
            ).toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
    });
  }

  @override
  Future<List<Beneficiary>> getCachedBeneficiaries(String ashaId) async {
    final db = await _open();
    final rows = await db.query(
      'beneficiaries',
      where: "worker_id = ? AND deleted_at IS NULL AND status != 'closed'",
      whereArgs: [ashaId],
      orderBy: 'local_code ASC',
    );
    return rows
        .map(
          (r) => Beneficiary(
            id: r['local_code'] as String? ?? '',
            label: r['full_name'] as String? ?? '',
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
      await txn.delete(
        'cached_visit_summaries',
        where: 'asha_id = ?',
        whereArgs: [ashaId],
      );
      for (final v in visits) {
        await txn.insert(
          'cached_visit_summaries',
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
      'cached_visit_summaries',
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

  @override
  Future<BeneficiaryRecord> upsertBeneficiaryV2(
    BeneficiaryRecord record, {
    PregnancyRecord? pregnancy,
    ConsentRecord? consent,
    String? actorId,
  }) async {
    final db = await _open();
    final now = DateTime.now().toUtc().toIso8601String();
    late BeneficiaryRecord result;

    await db.transaction((txn) async {
      final existingRows = await txn.query(
        'beneficiaries',
        where: 'id = ?',
        whereArgs: [record.id],
        limit: 1,
      );
      if (existingRows.isNotEmpty) {
        final existing = BeneficiaryRecord.fromMap(existingRows.first);
        final isNewer = record.updatedAt.compareTo(existing.updatedAt) > 0 ||
            (record.updatedAt == existing.updatedAt &&
                record.version > existing.version);
        if (!isNewer) {
          result = existing;
          return;
        }
      }

      var saved = record;
      if (consent != null) {
        await txn.insert(
          'consents',
          consent.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        saved = saved.copyWith(consentId: consent.id);
      }
      if (saved.nextDueAt == null) {
        final due = DueEngine.computeNextDueAt(
          beneficiaryType: saved.beneficiaryType,
          dob: DueEngine.parseIsoDate(saved.dob),
          lmpDate: DueEngine.parseIsoDate(pregnancy?.lmpDate),
        );
        if (due != null) {
          saved = saved.copyWith(nextDueAt: DueEngine.formatIsoDate(due));
        }
      }

      await txn.insert(
        'beneficiaries',
        saved.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      if (pregnancy != null) {
        await txn.insert(
          'pregnancies',
          pregnancy.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await txn.insert(
        'audit_log',
        AuditLogEntry(
          id: UuidV4.generate(),
          actorId: actorId ?? saved.workerId,
          action: existingRows.isEmpty
              ? 'beneficiary_created'
              : 'beneficiary_updated',
          entity: 'beneficiary',
          entityId: saved.id,
          at: now,
        ).toMap(),
      );
      result = saved;
    });

    return result;
  }

  @override
  Future<List<BeneficiaryRecord>> getBeneficiariesV2(
    String workerId, {
    bool includeDeleted = false,
  }) async {
    final db = await _open();
    final where = includeDeleted
        ? 'worker_id = ?'
        : "worker_id = ? AND deleted_at IS NULL AND status != 'closed'";
    final rows = await db.query(
      'beneficiaries',
      where: where,
      whereArgs: [workerId],
      orderBy: 'next_due_at ASC, local_code ASC',
    );
    return rows.map(BeneficiaryRecord.fromMap).toList();
  }

  @override
  Future<BeneficiaryRecord?> getBeneficiaryV2(String beneficiaryId) async {
    final db = await _open();
    final rows = await db.query(
      'beneficiaries',
      where: 'id = ?',
      whereArgs: [beneficiaryId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return BeneficiaryRecord.fromMap(rows.first);
  }

  @override
  Future<void> softDeleteBeneficiaryV2(
    String beneficiaryId, {
    required String actorId,
  }) async {
    final db = await _open();
    final now = DateTime.now().toUtc().toIso8601String();
    await db.transaction((txn) async {
      await txn.rawUpdate(
        '''
        UPDATE beneficiaries
        SET deleted_at = ?, status = 'closed', updated_at = ?, version = version + 1
        WHERE id = ?
        ''',
        [now, now, beneficiaryId],
      );
      await txn.insert(
        'audit_log',
        AuditLogEntry(
          id: UuidV4.generate(),
          actorId: actorId,
          action: 'beneficiary_soft_deleted',
          entity: 'beneficiary',
          entityId: beneficiaryId,
          at: now,
        ).toMap(),
      );
    });
  }

  @override
  Future<void> saveConsent(ConsentRecord consent) async {
    final db = await _open();
    await db.insert(
      'consents',
      consent.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<List<ConsentRecord>> getConsentsForBeneficiary(
    String beneficiaryId,
  ) async {
    final db = await _open();
    final rows = await db.query(
      'consents',
      where: 'beneficiary_id = ?',
      whereArgs: [beneficiaryId],
      orderBy: 'given_at DESC',
    );
    return rows.map(ConsentRecord.fromMap).toList();
  }

  @override
  Future<VisitRecord> confirmVisitV2(
    VisitRecord visit, {
    int? intervalDays,
    DateTime? dob,
    DateTime? lmpDate,
    String? actorId,
  }) async {
    final db = await _open();
    final now = DateTime.now().toUtc().toIso8601String();
    late VisitRecord confirmed;

    await db.transaction((txn) async {
      final existingVisits = await txn.query(
        'visits',
        where: 'id = ?',
        whereArgs: [visit.id],
        limit: 1,
      );
      if (existingVisits.isNotEmpty) {
        final existingStatus = existingVisits.first['status'] as String? ?? 'draft';
        if (existingStatus == 'confirmed' || existingStatus == 'amended') {
          throw VisitImmutableException(
            'Visit ${visit.id} is already $existingStatus.',
          );
        }
      }

      String? nextDueStr = visit.nextDueAt;
      if (visit.beneficiaryId != null) {
        final benRows = await txn.query(
          'beneficiaries',
          where: 'id = ?',
          whereArgs: [visit.beneficiaryId],
          limit: 1,
        );
        if (benRows.isNotEmpty) {
          final ben = BeneficiaryRecord.fromMap(benRows.first);
          final nextDue = DueEngine.computeNextDueAt(
            beneficiaryType: ben.beneficiaryType,
            dob: dob ?? DueEngine.parseIsoDate(ben.dob),
            visitedAt: DueEngine.parseIsoDate(visit.visitedAt) ?? DateTime.now(),
            lmpDate: lmpDate,
            intervalDays: intervalDays,
          );
          nextDueStr =
              nextDue != null ? DueEngine.formatIsoDate(nextDue) : null;

          final shouldUpdateLastVisit = ben.lastVisitAt == null ||
              visit.visitedAt.compareTo(ben.lastVisitAt!) >= 0;

          await txn.update(
            'beneficiaries',
            {
              if (shouldUpdateLastVisit) 'last_visit_at': visit.visitedAt,
              'next_due_at': nextDueStr,
              'risk_level': DueEngine.deriveRiskLevel(
                visit.riskFlags,
                referralSuggested: visit.referralSuggested,
              ),
              'updated_at': now,
              'version': ben.version + 1,
            },
            where: 'id = ?',
            whereArgs: [ben.id],
          );
        }
      }

      confirmed = VisitRecord(
        id: visit.id,
        clientId: visit.clientId,
        beneficiaryId: visit.beneficiaryId,
        workerId: visit.workerId,
        visitTypeCode: visit.visitTypeCode,
        schemaVersion: visit.schemaVersion,
        visitedAt: visit.visitedAt,
        status: 'confirmed',
        payload: visit.payload,
        riskFlags: visit.riskFlags,
        referralSuggested: visit.referralSuggested,
        nextDueAt: nextDueStr,
        transcriptText: visit.transcriptText,
        language: visit.language,
        inputMethod: visit.inputMethod,
        startedAt: visit.startedAt,
        confirmedAt: now,
        updatedAt: now,
        version: visit.version + 1,
      );

      await txn.insert(
        'visits',
        confirmed.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      await txn.delete(
        'visit_measurements',
        where: 'visit_id = ?',
        whereArgs: [visit.id],
      );
      for (final m in DueEngine.extractNumericMeasurements(visit.payload)) {
        await txn.insert(
          'visit_measurements',
          VisitMeasurement(
            id: UuidV4.generate(),
            visitId: visit.id,
            beneficiaryId: visit.beneficiaryId,
            key: m.$1,
            valueNum: m.$2,
            unit: m.$3,
            measuredAt: visit.visitedAt,
          ).toMap(),
        );
      }

      await txn.insert(
        'audit_log',
        AuditLogEntry(
          id: UuidV4.generate(),
          actorId: actorId ?? visit.workerId,
          action: 'visit_confirmed',
          entity: 'visit',
          entityId: visit.id,
          at: now,
        ).toMap(),
      );
    });

    return confirmed;
  }

  @override
  Future<(VisitRecord, VisitAmendment)> amendVisitV2({
    required String visitId,
    required String changedBy,
    required Map<String, dynamic> changes,
    required String reason,
    List<String>? riskFlags,
    bool? referralSuggested,
  }) async {
    final db = await _open();
    final now = DateTime.now().toUtc().toIso8601String();
    late VisitRecord amended;
    late VisitAmendment amendment;

    await db.transaction((txn) async {
      final rows = await txn.query(
        'visits',
        where: 'id = ?',
        whereArgs: [visitId],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw StateError('Visit not found: $visitId');
      }
      final existing = VisitRecord.fromMap(rows.first);
      if (existing.status != 'confirmed' && existing.status != 'amended') {
        throw StateError('Only confirmed visits can be amended.');
      }

      final updatedPayload = Map<String, dynamic>.from(existing.payload);
      final diff = <String, dynamic>{};
      for (final entry in changes.entries) {
        diff[entry.key] = {
          'before': updatedPayload[entry.key],
          'after': entry.value,
        };
        updatedPayload[entry.key] = entry.value;
      }

      amendment = VisitAmendment(
        id: UuidV4.generate(),
        visitId: visitId,
        changedBy: changedBy,
        changes: diff,
        reason: reason.trim(),
        createdAt: now,
      );
      await txn.insert('visit_amendments', amendment.toMap());

      final mergedFlags = riskFlags ?? existing.riskFlags;
      final mergedReferral = referralSuggested ?? existing.referralSuggested;

      amended = VisitRecord(
        id: existing.id,
        clientId: existing.clientId,
        beneficiaryId: existing.beneficiaryId,
        workerId: existing.workerId,
        visitTypeCode: existing.visitTypeCode,
        schemaVersion: existing.schemaVersion,
        visitedAt: existing.visitedAt,
        status: 'amended',
        payload: updatedPayload,
        riskFlags: mergedFlags,
        referralSuggested: mergedReferral,
        nextDueAt: existing.nextDueAt,
        transcriptText: existing.transcriptText,
        language: existing.language,
        inputMethod: existing.inputMethod,
        startedAt: existing.startedAt,
        confirmedAt: existing.confirmedAt,
        updatedAt: now,
        version: existing.version + 1,
      );
      await txn.insert(
        'visits',
        amended.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      await txn.delete(
        'visit_measurements',
        where: 'visit_id = ?',
        whereArgs: [visitId],
      );
      for (final m in DueEngine.extractNumericMeasurements(updatedPayload)) {
        await txn.insert(
          'visit_measurements',
          VisitMeasurement(
            id: UuidV4.generate(),
            visitId: visitId,
            beneficiaryId: existing.beneficiaryId,
            key: m.$1,
            valueNum: m.$2,
            unit: m.$3,
            measuredAt: existing.visitedAt,
          ).toMap(),
        );
      }

      if (existing.beneficiaryId != null) {
        await txn.rawUpdate(
          '''
          UPDATE beneficiaries
          SET risk_level = ?, updated_at = ?, version = version + 1
          WHERE id = ?
          ''',
          [
            DueEngine.deriveRiskLevel(
              mergedFlags,
              referralSuggested: mergedReferral,
            ),
            now,
            existing.beneficiaryId,
          ],
        );
      }

      await txn.insert(
        'audit_log',
        AuditLogEntry(
          id: UuidV4.generate(),
          actorId: changedBy,
          action: 'visit_amended',
          entity: 'visit',
          entityId: visitId,
          at: now,
        ).toMap(),
      );
    });

    return (amended, amendment);
  }

  @override
  Future<List<VisitRecord>> getVisitsV2({
    String? workerId,
    String? beneficiaryId,
  }) async {
    final db = await _open();
    final clauses = <String>[];
    final args = <Object?>[];
    if (workerId != null) {
      clauses.add('worker_id = ?');
      args.add(workerId);
    }
    if (beneficiaryId != null) {
      clauses.add('beneficiary_id = ?');
      args.add(beneficiaryId);
    }
    final rows = await db.query(
      'visits',
      where: clauses.isEmpty ? null : clauses.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'visited_at DESC',
    );
    return rows.map(VisitRecord.fromMap).toList();
  }

  @override
  Future<List<VisitAmendment>> getVisitAmendments(String visitId) async {
    final db = await _open();
    final rows = await db.query(
      'visit_amendments',
      where: 'visit_id = ?',
      whereArgs: [visitId],
      orderBy: 'created_at ASC',
    );
    return rows.map(VisitAmendment.fromMap).toList();
  }

  @override
  Future<List<VisitMeasurement>> getVisitMeasurements(
    String beneficiaryId, {
    String? key,
  }) async {
    final db = await _open();
    final rows = await db.query(
      'visit_measurements',
      where: key != null ? 'beneficiary_id = ? AND key = ?' : 'beneficiary_id = ?',
      whereArgs: key != null ? [beneficiaryId, key] : [beneficiaryId],
      orderBy: 'measured_at ASC',
    );
    return rows.map(VisitMeasurement.fromMap).toList();
  }

  @override
  Future<List<AuditLogEntry>> getAuditLogs({String? entityId}) async {
    final db = await _open();
    final rows = await db.query(
      'audit_log',
      where: entityId != null ? 'entity_id = ?' : null,
      whereArgs: entityId != null ? [entityId] : null,
      orderBy: 'at ASC',
    );
    return rows.map(AuditLogEntry.fromMap).toList();
  }

  @override
  Future<void> enqueueSyncV2(SyncQueueEntry entry) async {
    final db = await _open();
    await db.insert(
      'sync_queue',
      entry.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<List<SyncQueueEntry>> getSyncQueueV2() async {
    final db = await _open();
    final rows = await db.query('sync_queue', orderBy: 'created_at ASC');
    return rows.map(SyncQueueEntry.fromMap).toList();
  }

  @override
  Future<void> markSyncAttemptV2(String id, {String? error}) async {
    final db = await _open();
    await db.rawUpdate(
      'UPDATE sync_queue SET attempts = attempts + 1, last_error = ? WHERE id = ?',
      [error, id],
    );
  }

  @override
  Future<void> removeSyncItemV2(String id) async {
    final db = await _open();
    await db.delete('sync_queue', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<void> saveAudioAsset(AudioAssetRecord asset) async {
    final db = await _open();
    await db.insert(
      'audio_assets',
      asset.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<List<String>> purgeExpiredAudioAssets({
    DateTime? now,
    Future<void> Function(String path)? deleteFile,
  }) async {
    final db = await _open();
    final refNow = now ?? DateTime.now().toUtc();
    final deleter = deleteFile ??
        (String path) async {
          final file = File(path);
          if (file.existsSync()) {
            await file.delete();
          }
        };
    final purged = <String>[];

    final rows = await db.query(
      'audio_assets',
      where: "state != 'deleted'",
    );
    for (final row in rows) {
      final asset = AudioAssetRecord.fromMap(row);
      var confirmed = false;
      if (asset.visitId != null) {
        final vRows = await db.query(
          'visits',
          columns: ['status'],
          where: 'id = ?',
          whereArgs: [asset.visitId],
          limit: 1,
        );
        if (vRows.isNotEmpty) {
          final st = vRows.first['status'] as String? ?? '';
          confirmed = st == 'confirmed' || st == 'amended';
        }
      }
      final deleteDt =
          asset.deleteAfter != null ? DateTime.tryParse(asset.deleteAfter!) : null;
      final expired = deleteDt != null && !deleteDt.isAfter(refNow);
      if (!(asset.state == 'uploaded' && confirmed) && !expired) {
        continue;
      }
      await deleter(asset.path);
      await db.transaction((txn) async {
        await txn.update(
          'audio_assets',
          {'state': 'deleted'},
          where: 'id = ?',
          whereArgs: [asset.id],
        );
        await txn.insert(
          'audit_log',
          AuditLogEntry(
            id: UuidV4.generate(),
            actorId: 'system_retention',
            action: 'audio_deleted',
            entity: 'audio_asset',
            entityId: asset.id,
            at: refNow.toIso8601String(),
          ).toMap(),
        );
      });
      purged.add(asset.id);
    }

    return purged;
  }
}
