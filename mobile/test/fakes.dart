import 'dart:async';
import 'dart:typed_data';

import 'package:asha_vaani/l10n/app_strings.dart';
import 'package:asha_vaani/models/beneficiary.dart';
import 'package:asha_vaani/models/newborn_visit.dart';
import 'package:asha_vaani/services/api_client.dart';
import 'package:asha_vaani/services/audio_player_service.dart';
import 'package:asha_vaani/services/audio_recorder_service.dart';
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
