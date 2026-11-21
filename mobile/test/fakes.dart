import 'dart:async';

import 'package:asha_vaani/models/beneficiary.dart';
import 'package:asha_vaani/models/newborn_visit.dart';
import 'package:asha_vaani/services/api_client.dart';
import 'package:asha_vaani/services/audio_player_service.dart';
import 'package:asha_vaani/services/audio_recorder_service.dart';

class FakeAshaApiClient implements AshaApiClient {
  bool healthy = true;
  List<Beneficiary> beneficiaries = const [
    Beneficiary(id: '1042', label: 'Baby of Sunita (synthetic)'),
    Beneficiary(id: '1043', label: 'Baby of Kavita (synthetic)'),
    Beneficiary(id: '1057', label: 'Baby of Lakshmi (synthetic)'),
  ];
  List<VisitSummary> savedVisits = const [];
  VisitTurnResponse? nextUploadResponse;
  final List<VisitTurnResponse> followupResponses = [];
  RecordPatchResponse? nextPatchResponse;
  ReadbackResponse readbackResponse = const ReadbackResponse(
    text: 'Please confirm. Beneficiary ID 1042, weight 2.5 kg, temperature 37.0 degrees Celsius.',
    audioUrl: '/v1/audio/readback-1',
  );

  final List<Map<String, dynamic>> answerCalls = [];
  final List<Map<String, dynamic>> patchCalls = [];
  final List<String> confirmCalls = [];

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
  Future<List<Beneficiary>> getBeneficiaries(String ashaId) async => beneficiaries;

  @override
  Future<VisitTurnResponse> uploadVisitAudio({
    required String filePath,
    required String language,
    required String ashaId,
    String? beneficiaryId,
    String? sessionId,
    String visitType = 'newborn_home_visit',
  }) async {
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
  Future<List<VisitSummary>> getSavedVisits(String ashaId) async => savedVisits;
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
