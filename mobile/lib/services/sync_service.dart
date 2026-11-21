import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/beneficiary.dart';
import '../models/newborn_visit.dart';
import 'api_client.dart';
import 'local_db_service.dart';

abstract class ConnectivityMonitor {
  Stream<bool> get onOnlineChanged;
  Future<bool> isOnline();
  void dispose();
}

class PlusConnectivityMonitor implements ConnectivityMonitor {
  PlusConnectivityMonitor({Connectivity? connectivity})
      : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  static bool _hasConnection(List<ConnectivityResult> results) {
    return results.any((r) => r != ConnectivityResult.none);
  }

  @override
  Stream<bool> get onOnlineChanged => _connectivity.onConnectivityChanged
      .map(_hasConnection)
      .distinct();

  @override
  Future<bool> isOnline() async {
    final results = await _connectivity.checkConnectivity();
    return _hasConnection(results);
  }

  @override
  void dispose() {}
}

class SyncService extends ChangeNotifier {
  SyncService({
    required LocalDbService localDb,
    required AshaApiClient Function() apiProvider,
    required ConnectivityMonitor connectivity,
    Future<String> Function(String tempPath, String clientId)? persistAudioFile,
    Future<Uint8List> Function(String path)? readAudioBytes,
    Future<void> Function(String path)? deleteAudioFile,
  })  : _localDb = localDb,
        _apiProvider = apiProvider,
        _connectivity = connectivity,
        _persistAudioFile = persistAudioFile ?? _defaultPersistAudioFile,
        _readAudioBytes = readAudioBytes ?? _defaultReadAudioBytes,
        _deleteAudioFile = deleteAudioFile ?? _defaultDeleteAudioFile;

  final LocalDbService _localDb;
  final AshaApiClient Function() _apiProvider;
  final ConnectivityMonitor _connectivity;
  final Future<String> Function(String tempPath, String clientId) _persistAudioFile;
  final Future<Uint8List> Function(String path) _readAudioBytes;
  final Future<void> Function(String path) _deleteAudioFile;

  StreamSubscription<bool>? _connSub;
  bool _started = false;
  bool _isSyncing = false;
  int _pendingCount = 0;
  int _counter = 0;
  DateTime? _lastSyncedAt;

  bool get isSyncing => _isSyncing;
  int get pendingCount => _pendingCount;
  DateTime? get lastSyncedAt => _lastSyncedAt;

  static Future<String> _defaultPersistAudioFile(
    String tempPath,
    String clientId,
  ) async {
    final docsDir = await getApplicationDocumentsDirectory();
    final queueDir = Directory(p.join(docsDir.path, 'offline_queue'));
    if (!queueDir.existsSync()) {
      queueDir.createSync(recursive: true);
    }
    final destPath = p.join(queueDir.path, '$clientId.wav');
    final source = File(tempPath);
    if (source.existsSync()) {
      await source.copy(destPath);
      try {
        await source.delete();
      } catch (_) {}
    }
    return destPath;
  }

  static Future<Uint8List> _defaultReadAudioBytes(String path) async {
    return File(path).readAsBytes();
  }

  static Future<void> _defaultDeleteAudioFile(String path) async {
    try {
      final f = File(path);
      if (f.existsSync()) {
        await f.delete();
      }
    } catch (_) {}
  }

  Future<void> start() async {
    if (_started) return;
    _started = true;
    await refreshPendingCount();
    _connSub = _connectivity.onOnlineChanged.listen((online) {
      if (online) {
        syncPending();
      }
    });
    if (_pendingCount > 0) {
      try {
        if (await _connectivity.isOnline()) {
          await syncPending();
        }
      } catch (_) {}
    }
  }

  Future<void> refreshPendingCount() async {
    final pending = await _localDb.getPendingQueue();
    if (_pendingCount != pending.length) {
      _pendingCount = pending.length;
      notifyListeners();
    }
  }

  Future<QueuedAudioItem> saveRecordingOffline({
    required String tempFilePath,
    required String ashaId,
    required Beneficiary beneficiary,
    required String language,
    String visitType = 'newborn_home_visit',
  }) async {
    _counter += 1;
    final clientId =
        'offline_${DateTime.now().microsecondsSinceEpoch}_$_counter';
    final savedPath = await _persistAudioFile(tempFilePath, clientId);
    final item = QueuedAudioItem(
      clientId: clientId,
      ashaId: ashaId,
      beneficiaryId: beneficiary.id,
      beneficiaryLabel: beneficiary.label,
      audioPath: savedPath,
      language: language,
      visitType: visitType,
      status: 'pending',
      recordedAt: DateTime.now().toUtc().toIso8601String(),
    );
    await _localDb.enqueueAudio(item);
    await refreshPendingCount();
    notifyListeners();
    return item;
  }

  Future<int> syncPending() async {
    if (_isSyncing) return 0;
    final pending = await _localDb.getPendingQueue();
    if (pending.isEmpty) {
      if (_pendingCount != 0) {
        _pendingCount = 0;
        notifyListeners();
      }
      return 0;
    }

    _isSyncing = true;
    notifyListeners();
    var synced = 0;

    try {
      final batch = <SyncBatchItem>[];
      final byId = <String, QueuedAudioItem>{};

      for (final item in pending) {
        try {
          final bytes = await _readAudioBytes(item.audioPath);
          if (bytes.isEmpty) {
            await _localDb.markQueueError(
              item.clientId,
              'Empty audio file',
              permanent: true,
            );
            continue;
          }
          byId[item.clientId] = item;
          batch.add(
            SyncBatchItem(
              clientId: item.clientId,
              audioBase64: base64Encode(bytes),
              filename: p.basename(item.audioPath),
              language: item.language,
              visitType: item.visitType,
              beneficiaryId: item.beneficiaryId,
              ashaId: item.ashaId,
              recordedAt: item.recordedAt,
            ),
          );
        } catch (_) {
          await _localDb.markQueueError(
            item.clientId,
            'Missing audio file',
            permanent: true,
          );
        }
      }

      if (batch.isNotEmpty) {
        final results = await _apiProvider().syncOfflineQueue(batch);
        for (final res in results) {
          final item = byId[res.clientId];
          if (item == null) continue;
          if (res.ok && res.result != null) {
            await _localDb.saveDraft(
              LocalDraft(
                sessionId: res.result!.sessionId,
                clientId: item.clientId,
                ashaId: item.ashaId,
                beneficiaryId: item.beneficiaryId,
                turn: res.result!,
                status: 'ready_to_review',
                updatedAt: DateTime.now().toUtc().toIso8601String(),
              ),
            );
            await _localDb.markQueueSynced(item.clientId);
            await _deleteAudioFile(item.audioPath);
            synced += 1;
          } else {
            final permanent = res.errorCode == 'INVALID_AUDIO' ||
                res.errorCode == 'INVALID_VISIT_TYPE' ||
                res.errorCode == 'INVALID_LANGUAGE';
            await _localDb.markQueueError(
              item.clientId,
              res.errorMessage ?? res.errorCode ?? 'Sync failed',
              permanent: permanent,
            );
          }
        }
        if (synced > 0) {
          _lastSyncedAt = DateTime.now().toUtc();
          try {
            await _localDb.purgeExpiredAudioAssets(
              deleteFile: _deleteAudioFile,
            );
          } catch (_) {}
        }
      }
    } on ApiException {
      // Keep remaining items pending when offline or server unreachable.
    } finally {
      _isSyncing = false;
      final remaining = await _localDb.getPendingQueue();
      _pendingCount = remaining.length;
      notifyListeners();
    }

    return synced;
  }

  @override
  void dispose() {
    _connSub?.cancel();
    _connectivity.dispose();
    super.dispose();
  }
}
