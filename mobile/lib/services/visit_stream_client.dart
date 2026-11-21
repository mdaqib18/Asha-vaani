import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../models/newborn_visit.dart';

enum StreamEventType { partial, finalText, fields, followup, error }

class StreamServerEvent {
  const StreamServerEvent({
    required this.type,
    this.text = '',
    this.utteranceId,
    this.sessionId,
    this.status,
    this.record,
    this.flags = const [],
    this.riskFlags = const [],
    this.referralSuggested = false,
    this.followup,
    this.errorCode,
    this.errorMessage,
  });

  final StreamEventType type;
  final String text;
  final int? utteranceId;
  final String? sessionId;
  final String? status;
  final NewbornVisitRecord? record;
  final List<ValidationFlag> flags;
  final List<String> riskFlags;
  final bool referralSuggested;
  final FollowupPayload? followup;
  final String? errorCode;
  final String? errorMessage;

  factory StreamServerEvent.fromJson(Map<String, dynamic> json) {
    final typeRaw = (json['type'] as String? ?? '').trim().toLowerCase();
    switch (typeRaw) {
      case 'partial':
        return StreamServerEvent(
          type: StreamEventType.partial,
          text: json['text'] as String? ?? '',
        );
      case 'final':
        return StreamServerEvent(
          type: StreamEventType.finalText,
          text: json['text'] as String? ?? '',
          utteranceId: (json['utterance_id'] as num?)?.toInt(),
        );
      case 'fields':
        final recordRaw = json['record'];
        return StreamServerEvent(
          type: StreamEventType.fields,
          text: json['transcript'] as String? ?? '',
          sessionId: json['session_id'] as String?,
          status: json['status'] as String?,
          record: recordRaw is Map<String, dynamic>
              ? NewbornVisitRecord.fromJson(recordRaw)
              : null,
          flags: (json['flags'] as List<dynamic>?)
                  ?.whereType<Map<String, dynamic>>()
                  .map(ValidationFlag.fromJson)
                  .toList() ??
              const [],
          riskFlags: (json['risk_flags'] as List<dynamic>?)
                  ?.map((e) => e.toString())
                  .toList() ??
              const [],
          referralSuggested: json['referral_suggested'] as bool? ?? false,
        );
      case 'followup':
        return StreamServerEvent(
          type: StreamEventType.followup,
          sessionId: json['session_id'] as String?,
          followup: FollowupPayload.fromJson(json),
        );
      case 'error':
      default:
        return StreamServerEvent(
          type: StreamEventType.error,
          errorCode: json['code'] as String? ?? 'STT_STREAM_FAILED',
          errorMessage: json['message'] as String? ?? 'Streaming failed.',
        );
    }
  }
}

abstract class VisitStreamSession {
  Stream<StreamServerEvent> get events;
  void sendPcm(Uint8List chunk);
  Future<void> stop();
  Future<void> close();
}

abstract class VisitStreamClient {
  Future<VisitStreamSession> connect({
    required String baseUrl,
    required String language,
    required String visitType,
    String? sessionId,
    String? beneficiaryId,
    String? ashaId,
    String? authToken,
  });
}

class IoVisitStreamClient implements VisitStreamClient {
  static Uri buildStreamUri(String baseUrl) {
    final parsed = Uri.parse(baseUrl.trim());
    final wsScheme = parsed.scheme == 'https' ? 'wss' : 'ws';
    final cleanPath = parsed.path.endsWith('/')
        ? parsed.path.substring(0, parsed.path.length - 1)
        : parsed.path;
    return parsed.replace(scheme: wsScheme, path: '$cleanPath/v1/stream');
  }

  @override
  Future<VisitStreamSession> connect({
    required String baseUrl,
    required String language,
    required String visitType,
    String? sessionId,
    String? beneficiaryId,
    String? ashaId,
    String? authToken,
  }) async {
    final uri = buildStreamUri(baseUrl);
    final headers = <String, dynamic>{};
    if (authToken != null && authToken.isNotEmpty) {
      headers['Authorization'] = 'Bearer $authToken';
    }
    final socket = await WebSocket.connect(
      uri.toString(),
      headers: headers.isEmpty ? null : headers,
    ).timeout(const Duration(seconds: 6));

    socket.add(
      jsonEncode({
        'type': 'start',
        'language': language,
        'visit_type': visitType,
        if (sessionId != null) 'session_id': sessionId,
        if (beneficiaryId != null) 'beneficiary_id': beneficiaryId,
        if (ashaId != null) 'asha_id': ashaId,
      }),
    );

    return _IoVisitStreamSession(socket);
  }
}

class _IoVisitStreamSession implements VisitStreamSession {
  _IoVisitStreamSession(this._socket) {
    _sub = _socket.listen(
      (dynamic data) {
        if (data is String && data.trim().isNotEmpty) {
          try {
            final decoded = jsonDecode(data);
            if (decoded is Map<String, dynamic>) {
              _events.add(StreamServerEvent.fromJson(decoded));
            }
          } catch (_) {}
        }
      },
      onError: (Object err) {
        if (!_events.isClosed) {
          _events.add(
            StreamServerEvent(
              type: StreamEventType.error,
              errorCode: 'STT_STREAM_FAILED',
              errorMessage: err.toString(),
            ),
          );
          _events.close();
        }
      },
      onDone: () {
        if (!_events.isClosed) {
          _events.close();
        }
      },
      cancelOnError: false,
    );
  }

  final WebSocket _socket;
  final StreamController<StreamServerEvent> _events =
      StreamController<StreamServerEvent>.broadcast();
  late final StreamSubscription<dynamic> _sub;
  bool _closed = false;

  @override
  Stream<StreamServerEvent> get events => _events.stream;

  @override
  void sendPcm(Uint8List chunk) {
    if (_closed || chunk.isEmpty) return;
    _socket.add(chunk);
  }

  @override
  Future<void> stop() async {
    if (_closed) return;
    _socket.add(jsonEncode({'type': 'stop'}));
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _sub.cancel();
    await _socket.close();
    if (!_events.isClosed) {
      await _events.close();
    }
  }
}
