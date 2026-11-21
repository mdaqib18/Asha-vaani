import 'dart:io';

import 'package:dio/dio.dart';

import '../models/beneficiary.dart';
import '../models/newborn_visit.dart';
import '../models/visit_type.dart';

class ApiException implements Exception {
  const ApiException(this.code, [this.message, this.statusCode]);

  final String code;
  final String? message;
  final int? statusCode;

  @override
  String toString() => 'ApiException($code, $statusCode, $message)';
}

abstract class AshaApiClient {
  String resolveAudioUrl(String pathOrUrl);
  Future<bool> checkHealth();
  Future<LoginResult> login({required String workerCode, required String pin});
  Future<List<VisitTypeSummary>> getVisitTypes({String? beneficiaryType});
  Future<SuggestedPurposeResult> getSuggestedPurpose(
    String beneficiaryId, {
    String? beneficiaryType,
    String? dob,
    String? spokenHint,
  });
  Future<List<Beneficiary>> getBeneficiaries(String ashaId);
  Future<Beneficiary> createBeneficiary(BeneficiaryCreatePayload payload);
  Future<Beneficiary> getBeneficiaryProfile(String beneficiaryId);
  Future<BeneficiaryProfileVisits> getBeneficiaryVisits(String beneficiaryId);
  Future<List<DuplicateMatchItem>> checkDuplicateBeneficiary({
    required String workerId,
    String? areaId,
    required String fullName,
    String? dob,
    String? phone,
  });
  Future<BeneficiaryAudioExtractResult> extractBeneficiaryFromAudio({
    required String filePath,
    required String language,
    required String workerId,
    String? areaId,
  });
  Future<VisitTurnResponse> uploadVisitAudio({
    required String filePath,
    required String language,
    required String ashaId,
    String? beneficiaryId,
    String? sessionId,
    String visitType = 'newborn_home_visit',
  });
  Future<VisitTurnResponse> submitFollowupAnswer({
    required String sessionId,
    required String filePath,
    required String language,
  });
  Future<RecordPatchResponse> patchVisitRecord(
    String sessionId,
    Map<String, dynamic> fields, {
    String source = 'typed',
  });
  Future<String> confirmVisit(String sessionId);
  Future<ReadbackResponse> getReadback(String sessionId, String language);
  Future<List<VisitSummary>> getSavedVisits(String ashaId);
  Future<List<VisitSummary>> getFlaggedVisits();
  Future<VisitDetail> getVisitDetail(String sessionId);
  Future<List<SyncItemResult>> syncOfflineQueue(List<SyncBatchItem> items);
}

class DioAshaApiClient implements AshaApiClient {
  DioAshaApiClient({required String baseUrl})
      : _dio = Dio(
          BaseOptions(
            baseUrl: _normalizeBaseUrl(baseUrl),
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 75),
          ),
        );

  final Dio _dio;

  @override
  String resolveAudioUrl(String pathOrUrl) {
    final trimmed = pathOrUrl.trim();
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    final normalizedPath = trimmed.startsWith('/') ? trimmed : '/$trimmed';
    return '${_dio.options.baseUrl}$normalizedPath';
  }

  static String _normalizeBaseUrl(String url) {
    var trimmed = url.trim();
    while (trimmed.endsWith('/')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed;
  }

  ApiException _mapError(DioException e) {
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return const ApiException('TIMEOUT');
    }
    if (e.type == DioExceptionType.connectionError || e.error is SocketException) {
      return const ApiException('NETWORK_ERROR');
    }
    final resp = e.response;
    if (resp != null && resp.data is Map<String, dynamic>) {
      final data = resp.data as Map<String, dynamic>;
      final err = data['error'];
      if (err is Map<String, dynamic>) {
        return ApiException(
          err['code']?.toString() ?? 'REQUEST_FAILED',
          err['message']?.toString(),
          resp.statusCode,
        );
      }
    }
    return ApiException('REQUEST_FAILED', null, resp?.statusCode);
  }

  @override
  Future<bool> checkHealth() async {
    try {
      final resp = await _dio.get<Map<String, dynamic>>('/v1/health');
      return resp.statusCode == 200 && resp.data?['status'] == 'ok';
    } on DioException {
      return false;
    }
  }

  @override
  Future<LoginResult> login({
    required String workerCode,
    required String pin,
  }) async {
    try {
      final resp = await _dio.post<Map<String, dynamic>>(
        '/v1/auth/login',
        data: {'worker_code': workerCode.trim(), 'pin': pin.trim()},
      );
      return LoginResult.fromJson(resp.data ?? const {});
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  @override
  Future<List<VisitTypeSummary>> getVisitTypes({String? beneficiaryType}) async {
    try {
      final resp = await _dio.get<List<dynamic>>(
        '/v1/visit-types',
        queryParameters: {
          if (beneficiaryType != null && beneficiaryType.isNotEmpty)
            'beneficiary_type': beneficiaryType,
        },
      );
      final items = resp.data ?? const [];
      return items
          .whereType<Map<String, dynamic>>()
          .map(VisitTypeSummary.fromJson)
          .toList();
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  @override
  Future<SuggestedPurposeResult> getSuggestedPurpose(
    String beneficiaryId, {
    String? beneficiaryType,
    String? dob,
    String? spokenHint,
  }) async {
    try {
      final resp = await _dio.get<Map<String, dynamic>>(
        '/v1/beneficiaries/$beneficiaryId/suggested-purpose',
        queryParameters: {
          if (beneficiaryType != null && beneficiaryType.isNotEmpty)
            'beneficiary_type': beneficiaryType,
          if (dob != null && dob.isNotEmpty) 'dob': dob,
          if (spokenHint != null && spokenHint.isNotEmpty)
            'spoken_hint': spokenHint,
        },
      );
      return SuggestedPurposeResult.fromJson(resp.data ?? const {});
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  @override
  Future<List<Beneficiary>> getBeneficiaries(String ashaId) async {
    try {
      final resp = await _dio.get<List<dynamic>>(
        '/v1/beneficiaries',
        queryParameters: {'asha_id': ashaId},
      );
      final items = resp.data ?? const [];
      return items
          .whereType<Map<String, dynamic>>()
          .map(Beneficiary.fromJson)
          .toList();
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  @override
  Future<Beneficiary> createBeneficiary(BeneficiaryCreatePayload payload) async {
    try {
      final resp = await _dio.post<Map<String, dynamic>>(
        '/v1/beneficiaries',
        data: payload.toJson(),
      );
      return Beneficiary.fromJson(resp.data ?? const {});
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  @override
  Future<Beneficiary> getBeneficiaryProfile(String beneficiaryId) async {
    try {
      final resp =
          await _dio.get<Map<String, dynamic>>('/v1/beneficiaries/$beneficiaryId');
      return Beneficiary.fromJson(resp.data ?? const {});
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  @override
  Future<BeneficiaryProfileVisits> getBeneficiaryVisits(
    String beneficiaryId,
  ) async {
    try {
      final resp = await _dio.get<Map<String, dynamic>>(
        '/v1/beneficiaries/$beneficiaryId/visits',
      );
      return BeneficiaryProfileVisits.fromJson(resp.data ?? const {});
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  @override
  Future<List<DuplicateMatchItem>> checkDuplicateBeneficiary({
    required String workerId,
    String? areaId,
    required String fullName,
    String? dob,
    String? phone,
  }) async {
    try {
      final resp = await _dio.post<List<dynamic>>(
        '/v1/beneficiaries/check-duplicate',
        data: {
          'worker_id': workerId,
          if (areaId != null && areaId.isNotEmpty) 'area_id': areaId,
          'full_name': fullName,
          if (dob != null && dob.isNotEmpty) 'dob': dob,
          if (phone != null && phone.isNotEmpty) 'phone': phone,
        },
      );
      return (resp.data ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(DuplicateMatchItem.fromJson)
          .toList();
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  @override
  Future<BeneficiaryAudioExtractResult> extractBeneficiaryFromAudio({
    required String filePath,
    required String language,
    required String workerId,
    String? areaId,
  }) async {
    try {
      final filename = filePath.split(RegExp(r'[/\\]')).last;
      final formData = FormData.fromMap({
        'audio': await MultipartFile.fromFile(filePath, filename: filename),
        'language': language,
        'worker_id': workerId,
        if (areaId != null && areaId.isNotEmpty) 'area_id': areaId,
      });
      final resp = await _dio.post<Map<String, dynamic>>(
        '/v1/beneficiaries/from-audio',
        data: formData,
      );
      return BeneficiaryAudioExtractResult.fromJson(resp.data ?? const {});
    } on DioException catch (e) {
      throw _mapError(e);
    }
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
    try {
      final filename = filePath.split(RegExp(r'[/\\]')).last;
      final formData = FormData.fromMap({
        'audio': await MultipartFile.fromFile(filePath, filename: filename),
        'language': language,
        'visit_type': visitType,
        'asha_id': ashaId,
        if (beneficiaryId != null && beneficiaryId.isNotEmpty)
          'beneficiary_id': beneficiaryId,
        if (sessionId != null && sessionId.isNotEmpty) 'session_id': sessionId,
      });

      final resp = await _dio.post<Map<String, dynamic>>(
        '/v1/visits/audio',
        data: formData,
      );
      return VisitTurnResponse.fromJson(resp.data ?? const {});
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  @override
  Future<VisitTurnResponse> submitFollowupAnswer({
    required String sessionId,
    required String filePath,
    required String language,
  }) async {
    try {
      final filename = filePath.split(RegExp(r'[/\\]')).last;
      final formData = FormData.fromMap({
        'audio': await MultipartFile.fromFile(filePath, filename: filename),
        'language': language,
      });

      final resp = await _dio.post<Map<String, dynamic>>(
        '/v1/visits/$sessionId/answer',
        data: formData,
      );
      return VisitTurnResponse.fromJson(resp.data ?? const {});
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  @override
  Future<RecordPatchResponse> patchVisitRecord(
    String sessionId,
    Map<String, dynamic> fields, {
    String source = 'typed',
  }) async {
    try {
      final body = <String, dynamic>{...fields, 'source': source};
      final resp = await _dio.patch<Map<String, dynamic>>(
        '/v1/visits/$sessionId/record',
        data: body,
      );
      return RecordPatchResponse.fromJson(resp.data ?? const {});
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  @override
  Future<String> confirmVisit(String sessionId) async {
    try {
      final resp = await _dio.post<Map<String, dynamic>>(
        '/v1/visits/$sessionId/confirm',
      );
      return resp.data?['visit_id']?.toString() ?? '';
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  @override
  Future<ReadbackResponse> getReadback(String sessionId, String language) async {
    try {
      final resp = await _dio.get<Map<String, dynamic>>(
        '/v1/visits/$sessionId/readback',
        queryParameters: {'language': language},
      );
      return ReadbackResponse.fromJson(resp.data ?? const {});
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  @override
  Future<List<VisitSummary>> getSavedVisits(String ashaId) async {
    try {
      final resp = await _dio.get<List<dynamic>>(
        '/v1/visits',
        queryParameters: {'asha_id': ashaId},
      );
      final items = resp.data ?? const [];
      return items
          .whereType<Map<String, dynamic>>()
          .map(VisitSummary.fromJson)
          .toList();
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  @override
  Future<List<VisitSummary>> getFlaggedVisits() async {
    try {
      final resp = await _dio.get<List<dynamic>>(
        '/v1/visits',
        queryParameters: {'flagged_only': true},
      );
      final items = resp.data ?? const [];
      return items
          .whereType<Map<String, dynamic>>()
          .map(VisitSummary.fromJson)
          .toList();
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  @override
  Future<VisitDetail> getVisitDetail(String sessionId) async {
    try {
      final resp = await _dio.get<Map<String, dynamic>>('/v1/visits/$sessionId');
      return VisitDetail.fromJson(resp.data ?? const {});
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  @override
  Future<List<SyncItemResult>> syncOfflineQueue(List<SyncBatchItem> items) async {
    try {
      final resp = await _dio.post<Map<String, dynamic>>(
        '/v1/sync',
        data: items.map((e) => e.toJson()).toList(),
      );
      final rawResults = resp.data?['results'] as List<dynamic>? ?? const [];
      return rawResults
          .whereType<Map<String, dynamic>>()
          .map(SyncItemResult.fromJson)
          .toList();
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }
}
