import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:asha_vaani/l10n/app_strings.dart';
import 'package:asha_vaani/models/beneficiary.dart';
import 'package:asha_vaani/models/newborn_visit.dart';
import 'package:asha_vaani/models/v2_models.dart';
import 'package:asha_vaani/services/api_client.dart';
import 'package:asha_vaani/services/audio_player_service.dart';
import 'package:asha_vaani/services/audio_recorder_service.dart';
import 'package:asha_vaani/services/due_engine.dart';
import 'package:asha_vaani/services/local_db_service.dart';
import 'package:asha_vaani/services/sync_service.dart';
import 'package:asha_vaani/state/app_state.dart';

class FakeAshaApiClient implements AshaApiClient {
  bool healthy = true;
  ApiException? loginError;
  ApiException? beneficiariesError;
  ApiException? uploadError;
  ApiException? savedVisitsError;

  List<Beneficiary> beneficiaries = const [
    Beneficiary(id: '1042', label: 'Baby of Sunita (synthetic)'),
    Beneficiary(id: '1043', label: 'Baby of Kavita (synthetic)'),
    Beneficiary(id: '1057', label: 'Baby of Lakshmi (synthetic)'),
  ];
  List<VisitSummary> savedVisits = const [];
  List<VisitSummary> flaggedVisits = const [];
  final Map<String, VisitDetail> visitDetailsBySession = {};
  ApiException? flaggedVisitsError;
  VisitTurnResponse? nextUploadResponse;
  final List<VisitTurnResponse> followupResponses = [];
  RecordPatchResponse? nextPatchResponse;
  ReadbackResponse readbackResponse = const ReadbackResponse(
    text: 'Please confirm. Beneficiary ID 1042, weight 2.5 kg, temperature 37.0 degrees Celsius.',
    audioUrl: '/v1/audio/readback-1',
  );
  List<SyncItemResult> Function(List<SyncBatchItem> items)? onSyncBatch;

  final List<Map<String, dynamic>> answerCalls = [];
  final List<Map<String, dynamic>> patchCalls = [];
  final List<String> confirmCalls = [];
  final List<List<SyncBatchItem>> syncCalls = [];

  @override
  String resolveAudioUrl(String pathOrUrl) {
    if (pathOrUrl.startsWith('http://') || pathOrUrl.startsWith('https://')) {
      return pathOrUrl;
    }
    return 'http://10.0.2.2:8000$pathOrUrl';
  }

  @override
  Future<bool> checkHealth() async => healthy;

  @override
  Future<LoginResult> login({
    required String workerCode,
    required String pin,
  }) async {
    if (loginError != null) throw loginError!;
    final code = workerCode.trim().toLowerCase();
    final matched = AshaProfile.defaults.where((p) => p.id == code).toList();
    if (matched.isEmpty || pin.trim() != '1234') {
      throw const ApiException('INVALID_CREDENTIALS', 'Invalid worker code or PIN.', 401);
    }
    return LoginResult(token: 'fake-session-token', profile: matched.first);
  }

  @override
  Future<List<Beneficiary>> getBeneficiaries(String ashaId) async {
    if (beneficiariesError != null) throw beneficiariesError!;
    return beneficiaries;
  }

  @override
  Future<VisitTurnResponse> uploadVisitAudio({
    required String filePath,
    required String language,
    required String ashaId,
    String? beneficiaryId,
    String? sessionId,
    String visitType = 'newborn_home_visit',
  }) async {
    if (uploadError != null) throw uploadError!;
    return nextUploadResponse!;
  }

  @override
  Future<VisitTurnResponse> submitFollowupAnswer({
    required String sessionId,
    required String filePath,
    required String language,
  }) async {
    answerCalls.add({
      'sessionId': sessionId,
      'filePath': filePath,
      'language': language,
    });
    return followupResponses.removeAt(0);
  }

  @override
  Future<RecordPatchResponse> patchVisitRecord(
    String sessionId,
    Map<String, dynamic> fields, {
    String source = 'typed',
  }) async {
    patchCalls.add({'sessionId': sessionId, 'fields': fields, 'source': source});
    if (nextPatchResponse != null) return nextPatchResponse!;
    return RecordPatchResponse(
      sessionId: sessionId,
      record: NewbornVisitRecord(
        beneficiaryId: const ExtractedField(value: '1042', source: 'selected'),
        babyWeightKg: ExtractedField(
          value: (fields['baby_weight_kg'] as num?)?.toDouble() ?? 2.5,
          source: source,
        ),
      ),
      status: 'ready_to_confirm',
    );
  }

  @override
  Future<String> confirmVisit(String sessionId) async {
    confirmCalls.add(sessionId);
    return 'visit-uuid-1';
  }

  @override
  Future<ReadbackResponse> getReadback(String sessionId, String language) async {
    return readbackResponse;
  }

  @override
  Future<List<VisitSummary>> getSavedVisits(String ashaId) async {
    if (savedVisitsError != null) throw savedVisitsError!;
    return savedVisits;
  }

  @override
  Future<List<VisitSummary>> getFlaggedVisits() async {
    if (flaggedVisitsError != null) throw flaggedVisitsError!;
    return flaggedVisits;
  }

  @override
  Future<VisitDetail> getVisitDetail(String sessionId) async {
    final existing = visitDetailsBySession[sessionId];
    if (existing != null) return existing;
    return VisitDetail(
      sessionId: sessionId,
      status: 'saved',
      record: const NewbornVisitRecord(
        beneficiaryId: ExtractedField(value: '1043', source: 'selected'),
        babyWeightKg: ExtractedField(value: 2.2),
        temperatureC: ExtractedField(value: 37.8),
        riskFlags: ['low_birth_weight', 'fever'],
        referralSuggested: true,
      ),
    );
  }

  @override
  Future<List<SyncItemResult>> syncOfflineQueue(List<SyncBatchItem> items) async {
    syncCalls.add(items);
    if (onSyncBatch != null) {
      return onSyncBatch!(items);
    }
    return items
        .map(
          (item) => SyncItemResult(
            clientId: item.clientId,
            ok: true,
            result: VisitTurnResponse(
              sessionId: 'synced-${item.clientId}',
              transcript: 'Beneficiary ${item.beneficiaryId} weight 2.5 kg',
              record: NewbornVisitRecord(
                beneficiaryId: ExtractedField(
                  value: item.beneficiaryId ?? '1042',
                  source: 'selected',
                ),
                babyWeightKg: const ExtractedField(value: 2.5),
              ),
              status: 'ready_to_confirm',
            ),
          ),
        )
        .toList();
  }
}

class FakeAudioCaptureService implements AudioCaptureService {
  MicPermissionState permissionState = MicPermissionState.granted;
  int startCalls = 0;
  int stopCalls = 0;

  @override
  Future<MicPermissionState> ensurePermission() async => permissionState;

  @override
  Future<String> createTempWavPath() async => '/tmp/fake_visit_${startCalls + 1}.wav';

  @override
  Future<void> startRecording(String filePath) async {
    startCalls += 1;
  }

  @override
  Future<String?> stopRecording() async {
    stopCalls += 1;
    return '/tmp/fake_visit_$startCalls.wav';
  }

  @override
  Future<bool> openSettings() async => true;

  @override
  void dispose() {}
}

class FakeAudioPlaybackService implements AudioPlaybackService {
  final List<String> playedUrls = [];
  int stopCalls = 0;

  @override
  Future<void> playUrl(String url) async {
    playedUrls.add(url);
  }

  @override
  Future<void> stop() async {
    stopCalls += 1;
  }

  @override
  void dispose() {}
}

class FakeLocalDbService implements LocalDbService {
  final Map<String, List<Beneficiary>> beneficiariesByAsha = {};
  final Map<String, QueuedAudioItem> queue = {};
  final Map<String, LocalDraft> drafts = {};
  final Map<String, List<VisitSummary>> visitsByAsha = {};

  final Map<String, BeneficiaryRecord> beneficiariesV2 = {};
  final Map<String, PregnancyRecord> pregnanciesV2 = {};
  final Map<String, ConsentRecord> consentsV2 = {};
  final Map<String, VisitRecord> visitsV2 = {};
  final List<VisitMeasurement> measurementsV2 = [];
  final List<VisitAmendment> amendmentsV2 = [];
  final Map<String, SyncQueueEntry> syncQueueV2 = {};
  final Map<String, AudioAssetRecord> audioAssetsV2 = {};
  final List<AuditLogEntry> auditLogV2 = [];

  @override
  Future<void> cacheBeneficiaries(String ashaId, List<Beneficiary> items) async {
    beneficiariesByAsha[ashaId] = List.of(items);
  }

  @override
  Future<List<Beneficiary>> getCachedBeneficiaries(String ashaId) async {
    return List.of(beneficiariesByAsha[ashaId] ?? const []);
  }

  @override
  Future<void> enqueueAudio(QueuedAudioItem item) async {
    queue[item.clientId] = item;
  }

  @override
  Future<List<QueuedAudioItem>> getPendingQueue({String? ashaId}) async {
    return queue.values
        .where((i) => i.status == 'pending' && (ashaId == null || i.ashaId == ashaId))
        .toList();
  }

  @override
  Future<void> markQueueSynced(String clientId) async {
    final existing = queue[clientId];
    if (existing != null) {
      queue[clientId] = QueuedAudioItem(
        clientId: existing.clientId,
        ashaId: existing.ashaId,
        beneficiaryId: existing.beneficiaryId,
        beneficiaryLabel: existing.beneficiaryLabel,
        audioPath: existing.audioPath,
        language: existing.language,
        visitType: existing.visitType,
        status: 'synced',
        recordedAt: existing.recordedAt,
      );
    }
  }

  @override
  Future<void> markQueueError(
    String clientId,
    String message, {
    bool permanent = false,
  }) async {
    final existing = queue[clientId];
    if (existing != null) {
      queue[clientId] = QueuedAudioItem(
        clientId: existing.clientId,
        ashaId: existing.ashaId,
        beneficiaryId: existing.beneficiaryId,
        beneficiaryLabel: existing.beneficiaryLabel,
        audioPath: existing.audioPath,
        language: existing.language,
        visitType: existing.visitType,
        status: permanent ? 'error_permanent' : 'pending',
        recordedAt: existing.recordedAt,
        lastError: message,
      );
    }
  }

  @override
  Future<void> saveDraft(LocalDraft draft) async {
    drafts[draft.sessionId] = draft;
  }

  @override
  Future<List<LocalDraft>> getDrafts({String? ashaId}) async {
    return drafts.values
        .where((d) => ashaId == null || d.ashaId == ashaId)
        .toList();
  }

  @override
  Future<void> deleteDraft(String sessionId) async {
    drafts.remove(sessionId);
  }

  @override
  Future<void> cacheVisits(String ashaId, List<VisitSummary> visits) async {
    visitsByAsha[ashaId] = List.of(visits);
  }

  @override
  Future<List<VisitSummary>> getCachedVisits(String ashaId) async {
    return List.of(visitsByAsha[ashaId] ?? const []);
  }

  @override
  Future<BeneficiaryRecord> upsertBeneficiaryV2(
    BeneficiaryRecord record, {
    PregnancyRecord? pregnancy,
    ConsentRecord? consent,
    String? actorId,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final existing = beneficiariesV2[record.id];
    if (existing != null) {
      final isNewer = record.updatedAt.compareTo(existing.updatedAt) > 0 ||
          (record.updatedAt == existing.updatedAt &&
              record.version > existing.version);
      if (!isNewer) return existing;
    }

    var saved = record;
    if (consent != null) {
      consentsV2[consent.id] = consent;
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
    beneficiariesV2[saved.id] = saved;
    if (pregnancy != null) {
      pregnanciesV2[pregnancy.id] = pregnancy;
    }
    auditLogV2.add(
      AuditLogEntry(
        id: UuidV4.generate(),
        actorId: actorId ?? saved.workerId,
        action: existing == null ? 'beneficiary_created' : 'beneficiary_updated',
        entity: 'beneficiary',
        entityId: saved.id,
        at: now,
      ),
    );
    return saved;
  }

  @override
  Future<List<BeneficiaryRecord>> getBeneficiariesV2(
    String workerId, {
    bool includeDeleted = false,
  }) async {
    return beneficiariesV2.values
        .where(
          (b) =>
              b.workerId == workerId &&
              (includeDeleted || (b.deletedAt == null && b.status != 'closed')),
        )
        .toList()
      ..sort((a, b) => a.localCode.compareTo(b.localCode));
  }

  @override
  Future<BeneficiaryRecord?> getBeneficiaryV2(String beneficiaryId) async {
    return beneficiariesV2[beneficiaryId];
  }

  @override
  Future<void> softDeleteBeneficiaryV2(
    String beneficiaryId, {
    required String actorId,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final existing = beneficiariesV2[beneficiaryId];
    if (existing != null) {
      beneficiariesV2[beneficiaryId] = existing.copyWith(
        deletedAt: now,
        status: 'closed',
        updatedAt: now,
        version: existing.version + 1,
      );
    }
    auditLogV2.add(
      AuditLogEntry(
        id: UuidV4.generate(),
        actorId: actorId,
        action: 'beneficiary_soft_deleted',
        entity: 'beneficiary',
        entityId: beneficiaryId,
        at: now,
      ),
    );
  }

  @override
  Future<void> saveConsent(ConsentRecord consent) async {
    consentsV2[consent.id] = consent;
  }

  @override
  Future<List<ConsentRecord>> getConsentsForBeneficiary(
    String beneficiaryId,
  ) async {
    return consentsV2.values
        .where((c) => c.beneficiaryId == beneficiaryId)
        .toList();
  }

  @override
  Future<VisitRecord> confirmVisitV2(
    VisitRecord visit, {
    int? intervalDays,
    DateTime? dob,
    DateTime? lmpDate,
    String? actorId,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final existing = visitsV2[visit.id];
    if (existing != null &&
        (existing.status == 'confirmed' || existing.status == 'amended')) {
      throw VisitImmutableException(
        'Visit ${visit.id} is already ${existing.status}.',
      );
    }

    var nextDueStr = visit.nextDueAt;
    if (visit.beneficiaryId != null) {
      final ben = beneficiariesV2[visit.beneficiaryId!];
      if (ben != null) {
        final nextDue = DueEngine.computeNextDueAt(
          beneficiaryType: ben.beneficiaryType,
          dob: dob ?? DueEngine.parseIsoDate(ben.dob),
          visitedAt: DueEngine.parseIsoDate(visit.visitedAt) ?? DateTime.now(),
          lmpDate: lmpDate,
          intervalDays: intervalDays,
        );
        nextDueStr = nextDue != null ? DueEngine.formatIsoDate(nextDue) : null;
        final updateLast = ben.lastVisitAt == null ||
            visit.visitedAt.compareTo(ben.lastVisitAt!) >= 0;
        beneficiariesV2[ben.id] = ben.copyWith(
          lastVisitAt: updateLast ? visit.visitedAt : ben.lastVisitAt,
          nextDueAt: nextDueStr,
          riskLevel: DueEngine.deriveRiskLevel(
            visit.riskFlags,
            referralSuggested: visit.referralSuggested,
          ),
          updatedAt: now,
          version: ben.version + 1,
        );
      }
    }

    final confirmed = VisitRecord(
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
    visitsV2[visit.id] = confirmed;
    measurementsV2.removeWhere((m) => m.visitId == visit.id);
    for (final m in DueEngine.extractNumericMeasurements(visit.payload)) {
      measurementsV2.add(
        VisitMeasurement(
          id: UuidV4.generate(),
          visitId: visit.id,
          beneficiaryId: visit.beneficiaryId,
          key: m.$1,
          valueNum: m.$2,
          unit: m.$3,
          measuredAt: visit.visitedAt,
        ),
      );
    }
    auditLogV2.add(
      AuditLogEntry(
        id: UuidV4.generate(),
        actorId: actorId ?? visit.workerId,
        action: 'visit_confirmed',
        entity: 'visit',
        entityId: visit.id,
        at: now,
      ),
    );
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
    final now = DateTime.now().toUtc().toIso8601String();
    final existing = visitsV2[visitId];
    if (existing == null) throw StateError('Visit not found: $visitId');
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

    final amendment = VisitAmendment(
      id: UuidV4.generate(),
      visitId: visitId,
      changedBy: changedBy,
      changes: diff,
      reason: reason.trim(),
      createdAt: now,
    );
    amendmentsV2.add(amendment);

    final mergedFlags = riskFlags ?? existing.riskFlags;
    final mergedReferral = referralSuggested ?? existing.referralSuggested;
    final amended = VisitRecord(
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
    visitsV2[visitId] = amended;

    measurementsV2.removeWhere((m) => m.visitId == visitId);
    for (final m in DueEngine.extractNumericMeasurements(updatedPayload)) {
      measurementsV2.add(
        VisitMeasurement(
          id: UuidV4.generate(),
          visitId: visitId,
          beneficiaryId: existing.beneficiaryId,
          key: m.$1,
          valueNum: m.$2,
          unit: m.$3,
          measuredAt: existing.visitedAt,
        ),
      );
    }

    if (existing.beneficiaryId != null) {
      final ben = beneficiariesV2[existing.beneficiaryId!];
      if (ben != null) {
        beneficiariesV2[ben.id] = ben.copyWith(
          riskLevel: DueEngine.deriveRiskLevel(
            mergedFlags,
            referralSuggested: mergedReferral,
          ),
          updatedAt: now,
          version: ben.version + 1,
        );
      }
    }
    auditLogV2.add(
      AuditLogEntry(
        id: UuidV4.generate(),
        actorId: changedBy,
        action: 'visit_amended',
        entity: 'visit',
        entityId: visitId,
        at: now,
      ),
    );
    return (amended, amendment);
  }

  @override
  Future<List<VisitRecord>> getVisitsV2({
    String? workerId,
    String? beneficiaryId,
  }) async {
    return visitsV2.values
        .where(
          (v) =>
              (workerId == null || v.workerId == workerId) &&
              (beneficiaryId == null || v.beneficiaryId == beneficiaryId),
        )
        .toList();
  }

  @override
  Future<List<VisitAmendment>> getVisitAmendments(String visitId) async {
    return amendmentsV2.where((a) => a.visitId == visitId).toList();
  }

  @override
  Future<List<VisitMeasurement>> getVisitMeasurements(
    String beneficiaryId, {
    String? key,
  }) async {
    return measurementsV2
        .where(
          (m) =>
              m.beneficiaryId == beneficiaryId && (key == null || m.key == key),
        )
        .toList();
  }

  @override
  Future<List<AuditLogEntry>> getAuditLogs({String? entityId}) async {
    if (entityId == null) return List.of(auditLogV2);
    return auditLogV2.where((a) => a.entityId == entityId).toList();
  }

  @override
  Future<void> enqueueSyncV2(SyncQueueEntry entry) async {
    syncQueueV2[entry.id] = entry;
  }

  @override
  Future<List<SyncQueueEntry>> getSyncQueueV2() async {
    return syncQueueV2.values.toList();
  }

  @override
  Future<void> markSyncAttemptV2(String id, {String? error}) async {
    final existing = syncQueueV2[id];
    if (existing != null) {
      syncQueueV2[id] = SyncQueueEntry(
        id: existing.id,
        entity: existing.entity,
        entityId: existing.entityId,
        op: existing.op,
        attempts: existing.attempts + 1,
        lastError: error,
        createdAt: existing.createdAt,
      );
    }
  }

  @override
  Future<void> removeSyncItemV2(String id) async {
    syncQueueV2.remove(id);
  }

  @override
  Future<void> saveAudioAsset(AudioAssetRecord asset) async {
    audioAssetsV2[asset.id] = asset;
  }

  @override
  Future<List<String>> purgeExpiredAudioAssets({
    DateTime? now,
    Future<void> Function(String path)? deleteFile,
  }) async {
    final refNow = now ?? DateTime.now().toUtc();
    final deleter = deleteFile ??
        (String path) async {
          final file = File(path);
          if (file.existsSync()) {
            await file.delete();
          }
        };
    final purged = <String>[];
    for (final asset in audioAssetsV2.values.toList()) {
      if (asset.state == 'deleted') continue;
      final visit = asset.visitId != null ? visitsV2[asset.visitId!] : null;
      final confirmed =
          visit != null && (visit.status == 'confirmed' || visit.status == 'amended');
      final deleteDt =
          asset.deleteAfter != null ? DateTime.tryParse(asset.deleteAfter!) : null;
      final expired = deleteDt != null && !deleteDt.isAfter(refNow);
      if (!(asset.state == 'uploaded' && confirmed) && !expired) continue;
      await deleter(asset.path);
      audioAssetsV2[asset.id] = AudioAssetRecord(
        id: asset.id,
        visitId: asset.visitId,
        path: asset.path,
        durationMs: asset.durationMs,
        state: 'deleted',
        deleteAfter: asset.deleteAfter,
        createdAt: asset.createdAt,
      );
      auditLogV2.add(
        AuditLogEntry(
          id: UuidV4.generate(),
          actorId: 'system_retention',
          action: 'audio_deleted',
          entity: 'audio_asset',
          entityId: asset.id,
          at: refNow.toIso8601String(),
        ),
      );
      purged.add(asset.id);
    }
    return purged;
  }
}

class FakeConnectivityMonitor implements ConnectivityMonitor {
  FakeConnectivityMonitor({bool initialOnline = true}) : _online = initialOnline;

  final StreamController<bool> _controller = StreamController<bool>.broadcast();
  bool _online;

  void emitOnline(bool online) {
    _online = online;
    _controller.add(online);
  }

  @override
  Stream<bool> get onOnlineChanged => _controller.stream;

  @override
  Future<bool> isOnline() async => _online;

  @override
  void dispose() {
    _controller.close();
  }
}

AppState makeTestAppState({
  required FakeAshaApiClient api,
  FakeAudioCaptureService? recorder,
  FakeAudioPlaybackService? audioPlayer,
  FakeLocalDbService? localDb,
  FakeConnectivityMonitor? connectivity,
  AppLanguage initialLanguage = AppLanguage.en,
  AshaProfile? initialProfile,
  bool? initialLocked,
  bool? initialHighContrast,
}) {
  final db = localDb ?? FakeLocalDbService();
  final conn = connectivity ?? FakeConnectivityMonitor();
  final deletedPaths = <String>[];
  final sync = SyncService(
    localDb: db,
    apiProvider: () => api,
    connectivity: conn,
    persistAudioFile: (tempPath, clientId) async => '/offline/$clientId.wav',
    readAudioBytes: (path) async => Uint8List.fromList([82, 73, 70, 70]),
    deleteAudioFile: (path) async => deletedPaths.add(path),
  );
  return AppState(
    apiClient: api,
    recorder: recorder ?? FakeAudioCaptureService(),
    audioPlayer: audioPlayer ?? FakeAudioPlaybackService(),
    localDb: db,
    connectivity: conn,
    syncService: sync,
    initialLanguage: initialLanguage,
    initialProfile: initialProfile,
    initialLocked: initialLocked,
    initialHighContrast: initialHighContrast,
  );
}
