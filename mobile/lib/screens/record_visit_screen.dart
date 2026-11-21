import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../models/beneficiary.dart';
import '../services/api_client.dart';
import '../services/audio_recorder_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/language_toggle.dart';
import 'review_confirm_screen.dart';

class RecordVisitScreen extends StatefulWidget {
  const RecordVisitScreen({
    super.key,
    required this.appState,
    required this.beneficiary,
  });

  final AppState appState;
  final Beneficiary beneficiary;

  @override
  State<RecordVisitScreen> createState() => _RecordVisitScreenState();
}

class _RecordVisitScreenState extends State<RecordVisitScreen> {
  static const int _maxDurationSeconds = 29;
  static const int _minHoldMilliseconds = 500;

  bool _recording = false;
  bool _uploading = false;
  bool _permissionGranted = false;
  bool _permanentlyDenied = false;
  String? _statusMessage;
  bool _isErrorMessage = false;

  Timer? _timer;
  int _elapsedSeconds = 0;
  DateTime? _recordStartedAt;
  String? _activeFilePath;

  @override
  void initState() {
    super.initState();
    _checkMicPermission();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _checkMicPermission() async {
    final perm = await widget.appState.recorder.ensurePermission();
    if (!mounted) return;
    setState(() {
      _permissionGranted = perm == MicPermissionState.granted;
      _permanentlyDenied = perm == MicPermissionState.permanentlyDenied;
    });
  }

  Future<void> _startHoldRecording() async {
    if (_uploading || _recording) return;

    if (!_permissionGranted) {
      await _checkMicPermission();
      return;
    }

    try {
      final path = await widget.appState.recorder.createTempWavPath();
      await widget.appState.recorder.startRecording(path);
      if (!mounted) return;

      _timer?.cancel();
      setState(() {
        _activeFilePath = path;
        _recording = true;
        _elapsedSeconds = 0;
        _recordStartedAt = DateTime.now();
        _statusMessage = null;
        _isErrorMessage = false;
      });

      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted || !_recording) {
          timer.cancel();
          return;
        }
        setState(() => _elapsedSeconds += 1);
        if (_elapsedSeconds >= _maxDurationSeconds) {
          _stopAndUpload();
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _recording = false;
        _statusMessage = widget.appState.strings.friendlyError('INVALID_AUDIO');
        _isErrorMessage = true;
      });
    }
  }

  Future<void> _stopAndUpload() async {
    if (!_recording) return;
    _timer?.cancel();
    final startedAt = _recordStartedAt;
    setState(() => _recording = false);

    String? recordedPath;
    try {
      recordedPath = await widget.appState.recorder.stopRecording();
    } catch (_) {
      recordedPath = _activeFilePath;
    }
    final pathToUse = recordedPath ?? _activeFilePath;
    final heldMs = startedAt == null
        ? 0
        : DateTime.now().difference(startedAt).inMilliseconds;

    if (heldMs < _minHoldMilliseconds || pathToUse == null) {
      _cleanupTempFile(pathToUse);
      if (!mounted) return;
      setState(() {
        _statusMessage = widget.appState.strings.holdLongerHint;
        _isErrorMessage = false;
      });
      return;
    }

    await _uploadAudio(pathToUse);
  }

  Future<void> _uploadAudio(String filePath) async {
    final profile = widget.appState.selectedProfile;
    if (profile == null) return;

    setState(() {
      _uploading = true;
      _statusMessage = null;
      _isErrorMessage = false;
    });

    try {
      final turn = await widget.appState.api.uploadVisitAudio(
        filePath: filePath,
        language: widget.appState.language.code,
        ashaId: profile.id,
        beneficiaryId: widget.beneficiary.id,
      );
      _cleanupTempFile(filePath);
      if (!mounted) return;
      setState(() => _uploading = false);

      if (turn.status == 'error_retry') {
        setState(() {
          _statusMessage = widget.appState.strings.friendlyError('ERROR_RETRY');
          _isErrorMessage = true;
        });
        return;
      }

      final saved = await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          builder: (_) => ReviewConfirmScreen(
            appState: widget.appState,
            initialTurn: turn,
          ),
        ),
      );
      if (saved == true && mounted) {
        Navigator.of(context).pop(true);
      }
    } on ApiException catch (e) {
      _cleanupTempFile(filePath);
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _statusMessage = widget.appState.strings.friendlyError(e.code, e.message);
        _isErrorMessage = true;
      });
    }
  }

  void _cleanupTempFile(String? path) {
    if (path == null) return;
    try {
      final f = File(path);
      if (f.existsSync()) {
        f.deleteSync();
      }
    } catch (_) {}
  }

  String _formatTimer(int seconds) {
    final padded = seconds.toString().padLeft(2, '0');
    return '0:$padded / 0:30';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.appState,
      builder: (context, _) {
        final strings = widget.appState.strings;
        final statusLabel = _uploading
            ? strings.statusProcessing
            : (_recording ? strings.statusListening : strings.statusReady);

        return Scaffold(
          appBar: AppBar(
            title: Text(strings.recordVisitTitle),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: LanguageToggle(
                  selected: widget.appState.language,
                  onChanged: widget.appState.setLanguage,
                ),
              ),
            ],
          ),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primaryTint,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              widget.beneficiary.id,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: AppColors.primaryDark,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              widget.beneficiary.label,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _IconCueStrip(appState: widget.appState),
                  const Spacer(),
                  if (!_permissionGranted)
                    _PermissionPromptCard(
                      message: strings.micPermissionNeeded,
                      buttonLabel: _permanentlyDenied
                          ? strings.openSettings
                          : strings.grantPermission,
                      onPressed: () {
                        if (_permanentlyDenied) {
                          widget.appState.recorder.openSettings();
                        } else {
                          _checkMicPermission();
                        }
                      },
                    )
                  else ...[
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: _recording
                              ? AppColors.riskBg
                              : (_uploading
                                  ? AppColors.primaryTint
                                  : AppColors.surfaceSubtle),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: _recording
                                ? AppColors.riskBorder.withValues(alpha: 0.4)
                                : AppColors.border,
                          ),
                        ),
                        child: Text(
                          statusLabel,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: _recording
                                ? AppColors.riskText
                                : (_uploading
                                    ? AppColors.primaryDark
                                    : AppColors.inkSecondary),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Center(
                      child: Listener(
                        key: const ValueKey('push_to_talk_button'),
                        onPointerDown: (_) => _startHoldRecording(),
                        onPointerUp: (_) => _stopAndUpload(),
                        onPointerCancel: (_) => _stopAndUpload(),
                        child: AnimatedScale(
                          scale: _recording ? 1.07 : 1.0,
                          duration: const Duration(milliseconds: 140),
                          child: Container(
                            width: 164,
                            height: 164,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _recording
                                  ? AppColors.riskBg
                                  : AppColors.primaryTint,
                            ),
                            child: Center(
                              child: Container(
                                width: 132,
                                height: 132,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _uploading
                                      ? AppColors.surfaceSubtle
                                      : (_recording
                                          ? AppColors.riskText
                                          : AppColors.primary),
                                ),
                                child: Center(
                                  child: _uploading
                                      ? const SizedBox(
                                          width: 34,
                                          height: 34,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 3,
                                            color: AppColors.primary,
                                          ),
                                        )
                                      : Icon(
                                          _recording
                                              ? Icons.mic_rounded
                                              : Icons.mic_none_rounded,
                                          size: 52,
                                          color: Colors.white,
                                        ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      _recording
                          ? '${strings.releaseToSend} · ${_formatTimer(_elapsedSeconds)}'
                          : strings.holdToSpeak,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                  const Spacer(),
                  if (_statusMessage != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: _isErrorMessage
                            ? AppColors.riskBg
                            : AppColors.warningBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _isErrorMessage
                              ? AppColors.riskBorder.withValues(alpha: 0.4)
                              : AppColors.warningBorder.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _isErrorMessage
                                ? Icons.error_outline_rounded
                                : Icons.info_outline_rounded,
                            color: _isErrorMessage
                                ? AppColors.riskText
                                : AppColors.warningText,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _statusMessage!,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: _isErrorMessage
                                    ? AppColors.riskText
                                    : AppColors.warningText,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _IconCueStrip extends StatelessWidget {
  const _IconCueStrip({required this.appState});

  final AppState appState;

  @override
  Widget build(BuildContext context) {
    final s = appState.strings;
    final cues = [
      (Icons.monitor_weight_outlined, s.cueWeight),
      (Icons.thermostat_outlined, s.cueTemp),
      (Icons.child_care_outlined, s.cueFeeding),
      (Icons.healing_outlined, s.cueCord),
      (Icons.visibility_outlined, s.cueJaundice),
      (Icons.accessibility_new_outlined, s.cueLimbs),
    ];

    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: cues.map((cue) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(cue.$1, size: 15, color: AppColors.primary),
              const SizedBox(width: 5),
              Text(
                cue.$2,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.inkSecondary,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _PermissionPromptCard extends StatelessWidget {
  const _PermissionPromptCard({
    required this.message,
    required this.buttonLabel,
    required this.onPressed,
  });

  final String message;
  final String buttonLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.mic_off_rounded, size: 40, color: AppColors.warningText),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onPressed,
                child: Text(buttonLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
