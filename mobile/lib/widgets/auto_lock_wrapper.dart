import 'dart:async';

import 'package:flutter/widgets.dart';

import '../state/app_state.dart';

/// Auto-locks the app after backgrounding or foreground inactivity (`SPEC_V2 §7`).
class AutoLockWrapper extends StatefulWidget {
  const AutoLockWrapper({
    super.key,
    required this.appState,
    required this.child,
    this.now = _defaultNow,
  });

  final AppState appState;
  final Widget child;
  final DateTime Function() now;

  static DateTime _defaultNow() => DateTime.now().toUtc();

  @override
  State<AutoLockWrapper> createState() => _AutoLockWrapperState();
}

class _AutoLockWrapperState extends State<AutoLockWrapper>
    with WidgetsBindingObserver {
  DateTime? _backgroundedAt;
  Timer? _inactivityTimer;
  int _lastTimeoutSeconds = -1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.appState.addListener(_onAppStateChanged);
    _resetInactivityTimer();
  }

  @override
  void dispose() {
    _inactivityTimer?.cancel();
    widget.appState.removeListener(_onAppStateChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onAppStateChanged() {
    if (widget.appState.isLocked || widget.appState.selectedProfile == null) {
      _inactivityTimer?.cancel();
      _inactivityTimer = null;
      return;
    }
    if (_inactivityTimer == null ||
        _lastTimeoutSeconds != widget.appState.autoLockSeconds) {
      _resetInactivityTimer();
    }
  }

  void _resetInactivityTimer() {
    _inactivityTimer?.cancel();
    if (widget.appState.selectedProfile == null || widget.appState.isLocked) {
      _inactivityTimer = null;
      return;
    }
    final timeout = widget.appState.autoLockSeconds;
    _lastTimeoutSeconds = timeout;
    _inactivityTimer = Timer(Duration(seconds: timeout), () {
      if (!mounted) return;
      if (widget.appState.selectedProfile != null && !widget.appState.isLocked) {
        widget.appState.lockApp();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _backgroundedAt ??= widget.now();
      _inactivityTimer?.cancel();
    } else if (state == AppLifecycleState.resumed) {
      final bg = _backgroundedAt;
      _backgroundedAt = null;
      if (bg != null &&
          widget.appState.selectedProfile != null &&
          !widget.appState.isLocked) {
        final elapsed = widget.now().difference(bg).inSeconds;
        if (elapsed >= widget.appState.autoLockSeconds) {
          widget.appState.lockApp();
          return;
        }
      }
      _resetInactivityTimer();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _resetInactivityTimer(),
      child: widget.child,
    );
  }
}
