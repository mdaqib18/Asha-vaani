import 'dart:async';

import 'package:just_audio/just_audio.dart';

abstract class AudioPlaybackService {
  Future<void> playUrl(String url);
  Future<void> stop();
  void dispose();
}

class JustAudioPlaybackService implements AudioPlaybackService {
  JustAudioPlaybackService({AudioPlayer? player})
      : _player = player ?? AudioPlayer();

  final AudioPlayer _player;
  Completer<void>? _activeCompleter;

  void _completeActive() {
    final c = _activeCompleter;
    if (c != null && !c.isCompleted) {
      c.complete();
    }
    _activeCompleter = null;
  }

  @override
  Future<void> playUrl(String url) async {
    await stop();
    final completer = Completer<void>();
    _activeCompleter = completer;

    StreamSubscription<PlayerState>? sub;
    try {
      await _player.setUrl(url);
      var sawActive = false;
      sub = _player.playerStateStream.listen(
        (state) {
          if (state.playing ||
              state.processingState == ProcessingState.buffering ||
              state.processingState == ProcessingState.ready) {
            sawActive = true;
          }
          if (state.processingState == ProcessingState.completed ||
              (sawActive && state.processingState == ProcessingState.idle)) {
            _completeActive();
          }
        },
        onError: (_) => _completeActive(),
      );

      unawaited(_player.play().catchError((_) => _completeActive()));
      await completer.future;
    } finally {
      await sub?.cancel();
      _completeActive();
    }
  }

  @override
  Future<void> stop() async {
    _completeActive();
    try {
      await _player.stop();
    } catch (_) {}
  }

  @override
  void dispose() {
    _completeActive();
    _player.dispose();
  }
}
