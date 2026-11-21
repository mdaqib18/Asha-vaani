import 'dart:io';

import 'package:dio/dio.dart';

import '../models/beneficiary.dart';
import '../models/newborn_visit.dart';

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
  Future<List<Beneficiary>> getBeneficiaries(String ashaId);
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
}
