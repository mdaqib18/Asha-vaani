import 'dart:convert';
import 'dart:math';

/// Generates RFC 4122 version-4 UUID strings locally for offline-first records.
class UuidV4 {
  UuidV4._();

  static final Random _random = Random.secure();

  static String generate() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;

    String hex(int b) => b.toRadixString(16).padLeft(2, '0');
    final h = bytes.map(hex).join();
    return '${h.substring(0, 8)}-'
        '${h.substring(8, 12)}-'
        '${h.substring(12, 16)}-'
        '${h.substring(16, 20)}-'
        '${h.substring(20, 32)}';
  }
}

class BeneficiaryRecord {
  const BeneficiaryRecord({
    required this.id,
    required this.localCode,
    this.externalId,
    required this.workerId,
    this.areaId,
    this.householdId,
    required this.fullName,
    this.sex = 'unknown',
    this.dob,
    this.dobIsEstimated = false,
    this.beneficiaryType = 'newborn',
    this.motherId,
    this.phoneEnc,
    this.consentId,
    this.status = 'active',
    this.riskLevel = 'none',
    this.lastVisitAt,
    this.nextDueAt,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    this.version = 1,
  });

  final String id;
  final String localCode;
  final String? externalId;
  final String workerId;
  final String? areaId;
  final String? householdId;
  final String fullName;
  final String sex;
  final String? dob;
  final bool dobIsEstimated;
  final String beneficiaryType;
  final String? motherId;
  final String? phoneEnc;
  final String? consentId;
  final String status;
  final String riskLevel;
  final String? lastVisitAt;
  final String? nextDueAt;
  final String createdAt;
  final String updatedAt;
  final String? deletedAt;
  final int version;

  BeneficiaryRecord copyWith({
    String? localCode,
    String? externalId,
    String? areaId,
    String? householdId,
    String? fullName,
    String? sex,
    String? dob,
    bool? dobIsEstimated,
    String? beneficiaryType,
    String? motherId,
    String? phoneEnc,
    String? consentId,
    String? status,
    String? riskLevel,
    String? lastVisitAt,
    String? nextDueAt,
    String? updatedAt,
    String? deletedAt,
    int? version,
  }) {
    return BeneficiaryRecord(
      id: id,
      localCode: localCode ?? this.localCode,
      externalId: externalId ?? this.externalId,
      workerId: workerId,
      areaId: areaId ?? this.areaId,
      householdId: householdId ?? this.householdId,
      fullName: fullName ?? this.fullName,
      sex: sex ?? this.sex,
      dob: dob ?? this.dob,
      dobIsEstimated: dobIsEstimated ?? this.dobIsEstimated,
      beneficiaryType: beneficiaryType ?? this.beneficiaryType,
      motherId: motherId ?? this.motherId,
      phoneEnc: phoneEnc ?? this.phoneEnc,
      consentId: consentId ?? this.consentId,
      status: status ?? this.status,
      riskLevel: riskLevel ?? this.riskLevel,
      lastVisitAt: lastVisitAt ?? this.lastVisitAt,
      nextDueAt: nextDueAt ?? this.nextDueAt,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      version: version ?? this.version,
    );
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'local_code': localCode,
        'external_id': externalId,
        'worker_id': workerId,
        'area_id': areaId,
        'household_id': householdId,
        'full_name': fullName,
        'sex': sex,
        'dob': dob,
        'dob_is_estimated': dobIsEstimated ? 1 : 0,
        'beneficiary_type': beneficiaryType,
        'mother_id': motherId,
        'phone_enc': phoneEnc,
        'consent_id': consentId,
        'status': status,
        'risk_level': riskLevel,
        'last_visit_at': lastVisitAt,
        'next_due_at': nextDueAt,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'deleted_at': deletedAt,
        'version': version,
      };

  factory BeneficiaryRecord.fromMap(Map<String, Object?> row) => BeneficiaryRecord(
        id: row['id'] as String? ?? '',
        localCode: row['local_code'] as String? ?? '',
        externalId: row['external_id'] as String?,
        workerId: row['worker_id'] as String? ?? '',
        areaId: row['area_id'] as String?,
        householdId: row['household_id'] as String?,
        fullName: row['full_name'] as String? ?? '',
        sex: row['sex'] as String? ?? 'unknown',
        dob: row['dob'] as String?,
        dobIsEstimated: (row['dob_is_estimated'] as int? ?? 0) == 1,
        beneficiaryType: row['beneficiary_type'] as String? ?? 'newborn',
        motherId: row['mother_id'] as String?,
        phoneEnc: row['phone_enc'] as String?,
        consentId: row['consent_id'] as String?,
        status: row['status'] as String? ?? 'active',
        riskLevel: row['risk_level'] as String? ?? 'none',
        lastVisitAt: row['last_visit_at'] as String?,
        nextDueAt: row['next_due_at'] as String?,
        createdAt: row['created_at'] as String? ?? '',
        updatedAt: row['updated_at'] as String? ?? '',
        deletedAt: row['deleted_at'] as String?,
        version: row['version'] as int? ?? 1,
      );
}

class PregnancyRecord {
  const PregnancyRecord({
    required this.id,
    required this.beneficiaryId,
    this.lmpDate,
    this.eddDate,
    this.gravida,
    this.parity,
    this.outcome,
    this.status = 'active',
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String beneficiaryId;
  final String? lmpDate;
  final String? eddDate;
  final int? gravida;
  final int? parity;
  final String? outcome;
  final String status;
  final String createdAt;
  final String updatedAt;

  Map<String, Object?> toMap() => {
        'id': id,
        'beneficiary_id': beneficiaryId,
        'lmp_date': lmpDate,
        'edd_date': eddDate,
        'gravida': gravida,
        'parity': parity,
        'outcome': outcome,
        'status': status,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };
}

class VisitRecord {
  const VisitRecord({
    required this.id,
    this.clientId,
    this.beneficiaryId,
    required this.workerId,
    this.visitTypeCode = 'newborn_home_visit',
    this.schemaVersion = 1,
    required this.visitedAt,
    this.status = 'draft',
    required this.payload,
    this.riskFlags = const [],
    this.referralSuggested = false,
    this.nextDueAt,
    this.transcriptText = '',
    this.language = 'hi',
    this.inputMethod = 'voice',
    this.startedAt,
    this.confirmedAt,
    required this.updatedAt,
    this.version = 1,
  });

  final String id;
  final String? clientId;
  final String? beneficiaryId;
  final String workerId;
  final String visitTypeCode;
  final int schemaVersion;
  final String visitedAt;
  final String status;
  final Map<String, dynamic> payload;
  final List<String> riskFlags;
  final bool referralSuggested;
  final String? nextDueAt;
  final String transcriptText;
  final String language;
  final String inputMethod;
  final String? startedAt;
  final String? confirmedAt;
  final String updatedAt;
  final int version;

  Map<String, Object?> toMap() => {
        'id': id,
        'client_id': clientId,
        'beneficiary_id': beneficiaryId,
        'worker_id': workerId,
        'visit_type_code': visitTypeCode,
        'schema_version': schemaVersion,
        'visited_at': visitedAt,
        'status': status,
        'payload_json': jsonEncode(payload),
        'risk_flags_json': jsonEncode(riskFlags),
        'referral_suggested': referralSuggested ? 1 : 0,
        'next_due_at': nextDueAt,
        'transcript_text': transcriptText,
        'language': language,
        'input_method': inputMethod,
        'started_at': startedAt,
        'confirmed_at': confirmedAt,
        'updated_at': updatedAt,
        'version': version,
      };

  factory VisitRecord.fromMap(Map<String, Object?> row) {
    final payloadRaw = row['payload_json'] as String? ?? '{}';
    final flagsRaw = row['risk_flags_json'] as String? ?? '[]';
    return VisitRecord(
      id: row['id'] as String? ?? '',
      clientId: row['client_id'] as String?,
      beneficiaryId: row['beneficiary_id'] as String?,
      workerId: row['worker_id'] as String? ?? '',
      visitTypeCode: row['visit_type_code'] as String? ?? 'newborn_home_visit',
      schemaVersion: row['schema_version'] as int? ?? 1,
      visitedAt: row['visited_at'] as String? ?? '',
      status: row['status'] as String? ?? 'draft',
      payload: Map<String, dynamic>.from(jsonDecode(payloadRaw) as Map),
      riskFlags: (jsonDecode(flagsRaw) as List).map((e) => e.toString()).toList(),
      referralSuggested: (row['referral_suggested'] as int? ?? 0) == 1,
      nextDueAt: row['next_due_at'] as String?,
      transcriptText: row['transcript_text'] as String? ?? '',
      language: row['language'] as String? ?? 'hi',
      inputMethod: row['input_method'] as String? ?? 'voice',
      startedAt: row['started_at'] as String?,
      confirmedAt: row['confirmed_at'] as String?,
      updatedAt: row['updated_at'] as String? ?? '',
      version: row['version'] as int? ?? 1,
    );
  }
}

class VisitMeasurement {
  const VisitMeasurement({
    required this.id,
    required this.visitId,
    this.beneficiaryId,
    required this.key,
    required this.valueNum,
    required this.unit,
    required this.measuredAt,
  });

  final String id;
  final String visitId;
  final String? beneficiaryId;
  final String key;
  final double valueNum;
  final String unit;
  final String measuredAt;

  Map<String, Object?> toMap() => {
        'id': id,
        'visit_id': visitId,
        'beneficiary_id': beneficiaryId,
        'key': key,
        'value_num': valueNum,
        'unit': unit,
        'measured_at': measuredAt,
      };

  factory VisitMeasurement.fromMap(Map<String, Object?> row) => VisitMeasurement(
        id: row['id'] as String? ?? '',
        visitId: row['visit_id'] as String? ?? '',
        beneficiaryId: row['beneficiary_id'] as String?,
        key: row['key'] as String? ?? '',
        valueNum: (row['value_num'] as num? ?? 0).toDouble(),
        unit: row['unit'] as String? ?? '',
        measuredAt: row['measured_at'] as String? ?? '',
      );
}

class VisitAmendment {
  const VisitAmendment({
    required this.id,
    required this.visitId,
    required this.changedBy,
    required this.changes,
    required this.reason,
    required this.createdAt,
  });

  final String id;
  final String visitId;
  final String changedBy;
  final Map<String, dynamic> changes;
  final String reason;
  final String createdAt;

  Map<String, Object?> toMap() => {
        'id': id,
        'visit_id': visitId,
        'changed_by': changedBy,
        'changes_json': jsonEncode(changes),
        'reason': reason,
        'created_at': createdAt,
      };

  factory VisitAmendment.fromMap(Map<String, Object?> row) => VisitAmendment(
        id: row['id'] as String? ?? '',
        visitId: row['visit_id'] as String? ?? '',
        changedBy: row['changed_by'] as String? ?? '',
        changes: Map<String, dynamic>.from(
          jsonDecode(row['changes_json'] as String? ?? '{}') as Map,
        ),
        reason: row['reason'] as String? ?? '',
        createdAt: row['created_at'] as String? ?? '',
      );
}

class ConsentRecord {
  const ConsentRecord({
    required this.id,
    required this.beneficiaryId,
    this.kind = 'beneficiary_registration',
    this.givenBy = 'self',
    this.method = 'verbal',
    this.policyVersion = 'v2_2026_01',
    required this.givenAt,
  });

  final String id;
  final String beneficiaryId;
  final String kind;
  final String givenBy;
  final String method;
  final String policyVersion;
  final String givenAt;

  Map<String, Object?> toMap() => {
        'id': id,
        'beneficiary_id': beneficiaryId,
        'kind': kind,
        'given_by': givenBy,
        'method': method,
        'policy_version': policyVersion,
        'given_at': givenAt,
      };

  factory ConsentRecord.fromMap(Map<String, Object?> row) => ConsentRecord(
        id: row['id'] as String? ?? '',
        beneficiaryId: row['beneficiary_id'] as String? ?? '',
        kind: row['kind'] as String? ?? 'beneficiary_registration',
        givenBy: row['given_by'] as String? ?? 'self',
        method: row['method'] as String? ?? 'verbal',
        policyVersion: row['policy_version'] as String? ?? 'v2_2026_01',
        givenAt: row['given_at'] as String? ?? '',
      );
}

class AudioAssetRecord {
  const AudioAssetRecord({
    required this.id,
    this.visitId,
    required this.path,
    this.durationMs = 0,
    this.state = 'local',
    this.deleteAfter,
    required this.createdAt,
  });

  final String id;
  final String? visitId;
  final String path;
  final int durationMs;
  final String state;
  final String? deleteAfter;
  final String createdAt;

  Map<String, Object?> toMap() => {
        'id': id,
        'visit_id': visitId,
        'path': path,
        'duration_ms': durationMs,
        'state': state,
        'delete_after': deleteAfter,
        'created_at': createdAt,
      };

  factory AudioAssetRecord.fromMap(Map<String, Object?> row) => AudioAssetRecord(
        id: row['id'] as String? ?? '',
        visitId: row['visit_id'] as String?,
        path: row['path'] as String? ?? '',
        durationMs: row['duration_ms'] as int? ?? 0,
        state: row['state'] as String? ?? 'local',
        deleteAfter: row['delete_after'] as String?,
        createdAt: row['created_at'] as String? ?? '',
      );
}

class SyncQueueEntry {
  const SyncQueueEntry({
    required this.id,
    required this.entity,
    required this.entityId,
    required this.op,
    this.attempts = 0,
    this.lastError,
    required this.createdAt,
  });

  final String id;
  final String entity;
  final String entityId;
  final String op;
  final int attempts;
  final String? lastError;
  final String createdAt;

  Map<String, Object?> toMap() => {
        'id': id,
        'entity': entity,
        'entity_id': entityId,
        'op': op,
        'attempts': attempts,
        'last_error': lastError,
        'created_at': createdAt,
      };

  factory SyncQueueEntry.fromMap(Map<String, Object?> row) => SyncQueueEntry(
        id: row['id'] as String? ?? '',
        entity: row['entity'] as String? ?? '',
        entityId: row['entity_id'] as String? ?? '',
        op: row['op'] as String? ?? 'upsert',
        attempts: row['attempts'] as int? ?? 0,
        lastError: row['last_error'] as String?,
        createdAt: row['created_at'] as String? ?? '',
      );
}

class AuditLogEntry {
  const AuditLogEntry({
    required this.id,
    required this.actorId,
    required this.action,
    required this.entity,
    required this.entityId,
    this.deviceId = 'mobile',
    required this.at,
  });

  final String id;
  final String actorId;
  final String action;
  final String entity;
  final String entityId;
  final String deviceId;
  final String at;

  Map<String, Object?> toMap() => {
        'id': id,
        'actor_id': actorId,
        'action': action,
        'entity': entity,
        'entity_id': entityId,
        'device_id': deviceId,
        'at': at,
      };

  factory AuditLogEntry.fromMap(Map<String, Object?> row) => AuditLogEntry(
        id: row['id'] as String? ?? '',
        actorId: row['actor_id'] as String? ?? '',
        action: row['action'] as String? ?? '',
        entity: row['entity'] as String? ?? '',
        entityId: row['entity_id'] as String? ?? '',
        deviceId: row['device_id'] as String? ?? 'mobile',
        at: row['at'] as String? ?? '',
      );
}

class DuplicateCandidate {
  const DuplicateCandidate({
    required this.beneficiary,
    required this.score,
    required this.reasons,
  });

  final BeneficiaryRecord beneficiary;
  final double score;
  final List<String> reasons;
}

class VisitImmutableException implements Exception {
  const VisitImmutableException(this.message);
  final String message;

  @override
  String toString() => 'VisitImmutableException: $message';
}
