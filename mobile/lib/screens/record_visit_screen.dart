import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/beneficiary.dart';
import '../models/newborn_visit.dart';
import '../models/v2_models.dart';
import '../services/api_client.dart';
import '../services/audio_recorder_service.dart';
import '../services/visit_stream_client.dart';
import '../services/wav_encoder.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../ui/live_transcript.dart';
import '../widgets/language_toggle.dart';
import 'review_confirm_screen.dart';

class RecordVisitScreen extends StatefulWidget {
  const RecordVisitScreen({
    super.key,
    required this.appState,
    required this.beneficiary,
    this.visitTypeCode = 'newborn_home_visit',
    this.visitTypeLabel,
  });

  final AppState appState;
  final Beneficiary beneficiary;
  final String visitTypeCode;
  final String? visitTypeLabel;

  @override
  State<RecordVisitScreen> createState() => _RecordVisitScreenState();
}

class _RecordVisitScreenState extends State<RecordVisitScreen> {
  static const int _maxDurationSeconds = 29;
  static const int _minHoldMilliseconds = 500;

  bool _recording = false;
  bool _autoListening = false;
  bool _playingQuestion = false;
  bool _uploading = false;
  bool _savedOffline = false;
  bool _permissionGranted = false;
  bool _permanentlyDenied = false;
  late bool _visitConsentGiven;
  String _consentMethod = 'verbal';
  bool _savingConsent = false;
  String? _statusMessage;
  bool _isErrorMessage = false;

  String? _activeSessionId;
  VisitTurnResponse? _latestTurn;
  FollowupPayload? _activeFollowup;
  int _playbackToken = 0;

  Timer? _timer;
  Timer? _minHoldTimer;
  int _elapsedSeconds = 0;
  bool _heldLongEnough = false;
  String? _activeFilePath;

  bool _autoDetectLanguage = false;
  bool _streamingMode = false;
  bool _captionsPaused = false;
  String _finalizedTranscript = '';
  String _partialTranscript = '';
  double? _audioLevel;
  VisitStreamSession? _streamSession;
  StreamSubscription<Uint8List>? _pcmSub;
  StreamSubscription<StreamServerEvent>? _wsSub;
  final BytesBuilder _pcmBuffer = BytesBuilder(copy: false);
  StreamServerEvent? _streamFieldsEvent;
  FollowupPayload? _streamFollowup;
  Completer<void>? _streamCompletion;

  @override
  void initState() {
    super.initState();
    _visitConsentGiven = widget.beneficiary.consentRecorded;
    _checkConsentAndPermission();
  }

  Future<void> _checkConsentAndPermission() async {
    await _checkMicPermission();
    if (!_visitConsentGiven) {
      final benKey = widget.beneficiary.uuid ?? widget.beneficiary.id;
      final consents =
          await widget.appState.localDb.getConsentsForBeneficiary(benKey);
      if (!mounted) return;
      if (consents.isNotEmpty) {
        setState(() => _visitConsentGiven = true);
      }
    }
  }

  Future<void> _recordVisitConsent() async {
    if (_savingConsent) return;
    setState(() => _savingConsent = true);
    try {
      final now = DateTime.now().toUtc().toIso8601String();
      final benKey = widget.beneficiary.uuid ?? widget.beneficiary.id;
      final actorId = widget.appState.selectedProfile?.id ?? 'worker';
      final consentId = UuidV4.generate();
      await widget.appState.localDb.saveConsent(
        ConsentRecord(
          id: consentId,
          beneficiaryId: benKey,
          kind: 'visit_recording',
          givenBy: 'self',
          method: _consentMethod,
          givenAt: now,
        ),
      );
      await widget.appState.localDb.recordAuditLog(
        AuditLogEntry(
          id: UuidV4.generate(),
          actorId: actorId,
          action: 'visit_consent_recorded',
          entity: 'consent',
          entityId: consentId,
          at: now,
        ),
      );
      if (!mounted) return;
      setState(() => _visitConsentGiven = true);
    } finally {
      if (mounted) {
        setState(() => _savingConsent = false);
      }
    }
  }

  @override
  void dispose() {
    _playbackToken += 1;
    _timer?.cancel();
    _minHoldTimer?.cancel();
    _disposeStreamResources();
    widget.appState.audioPlayer.stop();
    super.dispose();
  }

  void _disposeStreamResources() {
    _pcmSub?.cancel();
    _pcmSub = null;
    _wsSub?.cancel();
    _wsSub = null;
    final session = _streamSession;
    _streamSession = null;
    if (session != null) {
      unawaited(session.close());
    }
    if (_streamCompletion != null && !_streamCompletion!.isCompleted) {
      _streamCompletion!.complete();
    }
    _streamCompletion = null;
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
    if (!_visitConsentGiven ||
        _uploading ||
        _recording ||
        _playingQuestion ||
        _autoListening) {
      return;
    }

    if (!_permissionGranted) {
      await _checkMicPermission();
      return;
    }

    await _beginRecording(autoListening: false);
  }

  Future<void> _startAutoFollowupRecording() async {
    if (!mounted ||
        !_visitConsentGiven ||
        _uploading ||
        _recording ||
        !_permissionGranted) {
      return;
    }
    await _beginRecording(autoListening: true);
  }

  Future<void> _connectStreamSession() async {
    final profile = widget.appState.selectedProfile;
    final streamLang =
        _autoDetectLanguage ? 'auto' : widget.appState.language.code;
    try {
      final session = await widget.appState.visitStream.connect(
        baseUrl: widget.appState.baseUrl,
        language: streamLang,
        visitType: widget.visitTypeCode,
        sessionId: _activeSessionId,
        beneficiaryId: widget.beneficiary.id,
        ashaId: profile?.id,
        authToken: widget.appState.sessionToken,
      );
      if (!mounted || (!_recording && !_uploading)) {
        await session.close();
        return;
      }
      _streamSession = session;
      _wsSub = session.events.listen(
        (ev) {
          if (!mounted) return;
          switch (ev.type) {
            case StreamEventType.partial:
              setState(() => _partialTranscript = ev.text);
              break;
            case StreamEventType.finalText:
              final piece = ev.text.trim();
              if (piece.isNotEmpty) {
                setState(() {
                  _finalizedTranscript = _finalizedTranscript.isEmpty
                      ? piece
                      : '$_finalizedTranscript $piece';
                  _partialTranscript = '';
                });
              }
              break;
            case StreamEventType.fields:
              _streamFieldsEvent = ev;
              if (ev.status != 'needs_followup' &&
                  _streamCompletion != null &&
                  !_streamCompletion!.isCompleted) {
                _streamCompletion!.complete();
              }
              break;
            case StreamEventType.followup:
              _streamFollowup = ev.followup;
              if (_streamCompletion != null && !_streamCompletion!.isCompleted) {
                _streamCompletion!.complete();
              }
              break;
            case StreamEventType.error:
              setState(() => _captionsPaused = true);
              if (_streamCompletion != null && !_streamCompletion!.isCompleted) {
                _streamCompletion!.complete();
              }
              break;
          }
        },
        onError: (_) {
          if (mounted && _streamFieldsEvent == null) {
            setState(() => _captionsPaused = true);
          }
          if (_streamCompletion != null && !_streamCompletion!.isCompleted) {
            _streamCompletion!.complete();
          }
        },
        onDone: () {
          if (mounted && _recording && _streamFieldsEvent == null) {
            setState(() => _captionsPaused = true);
          }
          if (_streamCompletion != null && !_streamCompletion!.isCompleted) {
            _streamCompletion!.complete();
          }
        },
      );
      final buffered = _pcmBuffer.toBytes();
      if (buffered.isNotEmpty && !_captionsPaused) {
        session.sendPcm(buffered);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _captionsPaused = true);
      }
    }
  }

  Future<void> _beginRecording({required bool autoListening}) async {
    try {
      _disposeStreamResources();
      _pcmBuffer.clear();

      Stream<Uint8List>? pcmStream;
      try {
        pcmStream = await widget.appState.recorder.startPcmStream();
      } catch (_) {
        pcmStream = null;
      }

      String? filePath;
      if (pcmStream == null) {
        filePath = await widget.appState.recorder.createTempWavPath();
        await widget.appState.recorder.startRecording(filePath);
      }
      if (!mounted) return;

      _timer?.cancel();
      _minHoldTimer?.cancel();
      setState(() {
        _activeFilePath = filePath;
        _streamingMode = pcmStream != null;
        _captionsPaused = false;
        _finalizedTranscript = '';
        _partialTranscript = '';
        _audioLevel = pcmStream != null ? 0.0 : null;
        _streamFieldsEvent = null;
        _streamFollowup = null;
        _recording = true;
        _autoListening = autoListening;
        _elapsedSeconds = 0;
        _heldLongEnough = autoListening;
        _statusMessage = null;
        _isErrorMessage = false;
      });

      if (pcmStream != null) {
        _pcmSub = pcmStream.listen((chunk) {
          if (chunk.isEmpty) return;
          _pcmBuffer.add(chunk);
          if (mounted) {
            setState(() => _audioLevel = WavEncoder.computeAudioLevel(chunk));
          }
          if (!_captionsPaused) {
            _streamSession?.sendPcm(chunk);
          }
        });
        unawaited(_connectStreamSession());
      }

      if (!autoListening) {
        _minHoldTimer = Timer(
          const Duration(milliseconds: _minHoldMilliseconds),
          () => _heldLongEnough = true,
        );
      }

      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted || !_recording) {
          timer.cancel();
          return;
        }
        setState(() => _elapsedSeconds += 1);
        if (_elapsedSeconds >= _maxDurationSeconds) {
          _stopAndUpload(checkMinHold: false);
        }
      });
    } catch (_) {
      _disposeStreamResources();
      if (!mounted) return;
      setState(() {
        _recording = false;
        _autoListening = false;
        _streamingMode = false;
        _statusMessage = widget.appState.strings.friendlyError('INVALID_AUDIO');
        _isErrorMessage = true;
      });
    }
  }

  Future<void> _stopAndUpload({required bool checkMinHold}) async {
    if (!_recording) return;
    _timer?.cancel();
    _minHoldTimer?.cancel();

    final heldEnough = _heldLongEnough;
    final wasStreaming = _streamingMode;
    setState(() {
      _recording = false;
      _autoListening = false;
      _audioLevel = null;
    });

    final pcmSub = _pcmSub;
    _pcmSub = null;
    if (pcmSub != null) {
      unawaited(pcmSub.cancel());
    }
    if (!mounted) return;

    String? recordedPath;
    try {
      recordedPath = await widget.appState.recorder.stopRecording();
    } catch (_) {
      recordedPath = _activeFilePath;
    }
    if (!mounted) return;

    if (wasStreaming) {
      final pcmBytes = _pcmBuffer.takeBytes();
      if (checkMinHold && (!heldEnough || pcmBytes.isEmpty)) {
        _disposeStreamResources();
        if (!mounted) return;
        setState(() {
          _streamingMode = false;
          _statusMessage = widget.appState.strings.holdLongerHint;
          _isErrorMessage = false;
        });
        return;
      }

      if (_streamSession != null && !_captionsPaused) {
        setState(() => _uploading = true);
        if (_streamFieldsEvent == null) {
          _streamCompletion = Completer<void>();
          try {
            await _streamSession!.stop();
            await _streamCompletion!.future.timeout(
              const Duration(seconds: 12),
              onTimeout: () {},
            );
          } catch (_) {
            if (mounted) {
              setState(() => _captionsPaused = true);
            }
          }
        }
        if (!mounted) {
          _disposeStreamResources();
          return;
        }
        final fieldsEv = _streamFieldsEvent;
        final followup = _streamFollowup;
        if (fieldsEv != null &&
            fieldsEv.record != null &&
            fieldsEv.status != null &&
            !_captionsPaused) {
          final turn = VisitTurnResponse(
            sessionId: fieldsEv.sessionId ?? (_activeSessionId ?? ''),
            transcript: fieldsEv.text,
            record: fieldsEv.record!,
            flags: fieldsEv.flags,
            riskFlags: fieldsEv.riskFlags,
            referralSuggested: fieldsEv.referralSuggested,
            status: fieldsEv.status!,
            followup: followup,
          );
          _disposeStreamResources();
          if (!mounted) return;
          setState(() => _uploading = false);
          await _handleTurnResponse(turn);
          return;
        }
      }

      // Automatic local WAV fallback when WebSocket dropped or produced no fields.
      _disposeStreamResources();
      if (pcmBytes.isEmpty) {
        if (mounted) {
          setState(() {
            _uploading = false;
            _statusMessage = widget.appState.strings.holdLongerHint;
          });
        }
        return;
      }
      final wavPath = await widget.appState.recorder.createTempWavPath();
      final wavBytes = WavEncoder.encodePcm16Mono(pcmBytes);
      final wavFile = File(wavPath);
      if (!wavFile.parent.existsSync()) {
        wavFile.parent.createSync(recursive: true);
      }
      wavFile.writeAsBytesSync(wavBytes, flush: true);
      await _uploadAudio(wavPath);
      return;
    }

    final pathToUse = recordedPath ?? _activeFilePath;

    if (checkMinHold && (!heldEnough || pathToUse == null)) {
      _cleanupTempFile(pathToUse);
      if (!mounted) return;
      setState(() {
        _statusMessage = widget.appState.strings.holdLongerHint;
        _isErrorMessage = false;
      });
      return;
    }

    if (pathToUse == null) return;
    await _uploadAudio(pathToUse);
  }

  Future<void> _uploadAudio(String filePath) async {
    final profile = widget.appState.selectedProfile;
    if (profile == null) return;

    setState(() {
      _uploading = true;
      _savedOffline = false;
      _statusMessage = null;
      _isErrorMessage = false;
    });

    final isFollowupTurn = _activeSessionId != null && _activeFollowup != null;
    try {
      final turn = isFollowupTurn
          ? await widget.appState.api.submitFollowupAnswer(
              sessionId: _activeSessionId!,
              filePath: filePath,
              language: widget.appState.language.code,
            )
          : await widget.appState.api.uploadVisitAudio(
              filePath: filePath,
              language: widget.appState.language.code,
              ashaId: profile.id,
              beneficiaryId: widget.beneficiary.id,
              sessionId: _activeSessionId,
              visitType: widget.visitTypeCode,
            );
      _cleanupTempFile(filePath);
      if (!mounted) return;
      setState(() => _uploading = false);

      await _handleTurnResponse(turn);
    } on ApiException catch (e) {
      if (!isFollowupTurn && (e.code == 'NETWORK_ERROR' || e.code == 'TIMEOUT')) {
        try {
          await widget.appState.syncService.saveRecordingOffline(
            tempFilePath: filePath,
            ashaId: profile.id,
            beneficiary: widget.beneficiary,
            language: widget.appState.language.code,
            visitType: widget.visitTypeCode,
          );
          if (!mounted) return;
          setState(() {
            _uploading = false;
            _savedOffline = true;
          });
          return;
        } catch (_) {
          // Fall back to standard error banner if offline save itself fails.
        }
      }
      _cleanupTempFile(filePath);
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _statusMessage = widget.appState.strings.friendlyError(e.code, e.message);
        _isErrorMessage = true;
      });
    }
  }

  Future<void> _handleTurnResponse(VisitTurnResponse turn) async {
    if (turn.status == 'error_retry') {
      setState(() {
        _statusMessage = widget.appState.strings.friendlyError('ERROR_RETRY');
        _isErrorMessage = true;
      });
      return;
    }

    setState(() {
      _activeSessionId = turn.sessionId;
      _latestTurn = turn;
    });

    if (turn.status == 'needs_followup' && turn.followup != null) {
      setState(() => _activeFollowup = turn.followup);
      await _playQuestionAndOpenMic(turn.followup!);
      return;
    }

    setState(() => _activeFollowup = null);
    await _openReviewScreen(turn);
  }

  Future<void> _playQuestionAndOpenMic(FollowupPayload followup) async {
    final myToken = ++_playbackToken;
    if (_recording) {
      _timer?.cancel();
      setState(() {
        _recording = false;
        _autoListening = false;
      });
      try {
        final droppedPath = await widget.appState.recorder.stopRecording();
        _cleanupTempFile(droppedPath ?? _activeFilePath);
      } catch (_) {}
    }

    final audioUrl = followup.questionAudioUrl;
    if (audioUrl != null && audioUrl.isNotEmpty) {
      if (!mounted) return;
      setState(() {
        _playingQuestion = true;
        _statusMessage = null;
      });
      try {
        await widget.appState.audioPlayer.playUrl(
          widget.appState.api.resolveAudioUrl(audioUrl),
        );
      } catch (_) {
        // Proceed to mic capture even if TTS playback fails on device.
      }
      if (!mounted || myToken != _playbackToken) return;
      setState(() => _playingQuestion = false);
    }

    if (!mounted || myToken != _playbackToken) return;
    await _startAutoFollowupRecording();
  }

  Future<void> _skipToReview() async {
    final turn = _latestTurn;
    if (turn == null) return;
    _playbackToken += 1;
    _timer?.cancel();
    if (_recording) {
      setState(() {
        _recording = false;
        _autoListening = false;
      });
      try {
        final droppedPath = await widget.appState.recorder.stopRecording();
        _cleanupTempFile(droppedPath ?? _activeFilePath);
      } catch (_) {}
    }
    if (_playingQuestion) {
      setState(() => _playingQuestion = false);
      await widget.appState.audioPlayer.stop();
    }
    if (!mounted) return;
    await _openReviewScreen(turn);
  }

  Future<void> _openReviewScreen(VisitTurnResponse turn) async {
    _playbackToken += 1;
    await widget.appState.audioPlayer.stop();
    if (!mounted) return;
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
            : (_playingQuestion
                ? strings.statusPlayingQuestion
                : (_recording ? strings.statusListening : strings.statusReady));

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
            child: SingleChildScrollView(
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
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.beneficiary.label,
                                  style: Theme.of(context).textTheme.titleMedium,
                                ),
                                if (widget.visitTypeLabel != null &&
                                    widget.visitTypeLabel!.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    '${strings.visitPurposeChipLabel}: ${widget.visitTypeLabel!}',
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (_activeFollowup != null)
                    _FollowupQuestionCard(
                      stepLabel: strings.followupStep(_activeFollowup!.followupCount),
                      questionText: _activeFollowup!.questionText,
                      replayLabel: strings.replayQuestion,
                      reviewLabel: strings.skipToReview,
                      canReplay: !_uploading && !_playingQuestion,
                      onReplay: () => _playQuestionAndOpenMic(_activeFollowup!),
                      onSkipToReview: _skipToReview,
                    )
                  else
                    _IconCueStrip(appState: widget.appState),
                  if (_streamingMode ||
                      _finalizedTranscript.isNotEmpty ||
                      _partialTranscript.isNotEmpty ||
                      _captionsPaused)
                    Padding(
                      key: const ValueKey('live_transcript_slot'),
                      padding: const EdgeInsets.only(top: AppSpacing.md),
                      child: LiveTranscript(
                        finalizedText: _finalizedTranscript,
                        partialText: _partialTranscript,
                        placeholder: strings.liveCaptionsPlaceholder,
                        pausedNotice: _captionsPaused
                            ? strings.liveCaptionsPausedNotice
                            : null,
                        audioLevel: _audioLevel,
                        label: strings.liveCaptionsTitle,
                      ),
                    ),
                  const SizedBox(height: AppSpacing.lg),
                  if (_savedOffline)
                    _SavedOfflineCard(
                      title: strings.savedOfflineTitle,
                      subtitle: strings.savedOfflineSubtitle,
                      buttonLabel: strings.done,
                      onDone: () => Navigator.of(context).pop(true),
                    )
                  else if (!_visitConsentGiven)
                    _VisitConsentCard(
                      title: strings.visitConsentTitle,
                      checkboxLabel: strings.visitConsentCheckbox,
                      verbalLabel: strings.consentMethodVerbal,
                      signedLabel: strings.consentMethodSigned,
                      method: _consentMethod,
                      saving: _savingConsent,
                      onMethodChanged: (m) => setState(() => _consentMethod = m),
                      onConfirmChanged: (checked) {
                        if (checked == true) {
                          _recordVisitConsent();
                        }
                      },
                    )
                  else if (!_permissionGranted)
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
                    Align(
                      key: const ValueKey('auto_detect_slot'),
                      alignment: Alignment.centerLeft,
                      child: FilterChip(
                        key: const ValueKey('auto_detect_language_toggle'),
                        avatar: const Icon(Icons.translate_rounded, size: 18),
                        label: Text(strings.autoDetectLanguageLabel),
                        selected: _autoDetectLanguage,
                        onSelected: _recording || _uploading
                            ? null
                            : (val) =>
                                setState(() => _autoDetectLanguage = val),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Center(
                      key: const ValueKey('status_pill_slot'),
                      child: Semantics(
                        liveRegion: true,
                        label: statusLabel,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: _recording
                                ? AppColors.riskBg
                                : ((_uploading || _playingQuestion)
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
                                  : ((_uploading || _playingQuestion)
                                      ? AppColors.primaryDark
                                      : AppColors.inkSecondary),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Center(
                      key: const ValueKey('mic_button_slot'),
                      child: _buildMicButton(),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      _autoListening
                          ? '${strings.tapWhenDone} · ${_formatTimer(_elapsedSeconds)}'
                          : (_recording
                              ? '${strings.releaseToSend} · ${_formatTimer(_elapsedSeconds)}'
                              : (_playingQuestion
                                  ? strings.statusPlayingQuestion
                                  : strings.holdToSpeak)),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                  const SizedBox(height: AppSpacing.lg),
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

  Widget _buildMicButton() {
    final outerColor = _recording
        ? AppColors.riskBg
        : AppColors.primaryTint;
    final innerColor = (_uploading || _playingQuestion)
        ? AppColors.surfaceSubtle
        : (_recording ? AppColors.riskText : AppColors.primary);

    final circle = AnimatedScale(
      scale: _recording ? 1.07 : 1.0,
      duration: const Duration(milliseconds: 140),
      child: Container(
        width: 164,
        height: 164,
        decoration: BoxDecoration(shape: BoxShape.circle, color: outerColor),
        child: Center(
          child: Container(
            width: 132,
            height: 132,
            decoration: BoxDecoration(shape: BoxShape.circle, color: innerColor),
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
                      _playingQuestion
                          ? Icons.volume_up_rounded
                          : (_autoListening
                              ? Icons.stop_rounded
                              : (_recording
                                  ? Icons.mic_rounded
                                  : Icons.mic_none_rounded)),
                      size: 52,
                      color: _playingQuestion ? AppColors.primary : Colors.white,
                    ),
            ),
          ),
        ),
      ),
    );

    final strings = widget.appState.strings;
    final micSemanticLabel = _autoListening
        ? strings.tapWhenDone
        : (_recording ? strings.releaseToSend : strings.holdToSpeak);

    if (_autoListening) {
      return Semantics(
        container: true,
        button: true,
        enabled: true,
        label: micSemanticLabel,
        excludeSemantics: true,
        child: GestureDetector(
          key: const ValueKey('stop_followup_button'),
          onTap: () => _stopAndUpload(checkMinHold: false),
          child: circle,
        ),
      );
    }

    if (_uploading || _playingQuestion) {
      return Semantics(
        container: true,
        button: true,
        enabled: false,
        label: _uploading ? strings.statusProcessing : strings.statusPlayingQuestion,
        excludeSemantics: true,
        child: IgnorePointer(child: circle),
      );
    }

    return Semantics(
      container: true,
      button: true,
      enabled: true,
      label: micSemanticLabel,
      excludeSemantics: true,
      child: Listener(
        key: const ValueKey('push_to_talk_button'),
        onPointerDown: (_) => _startHoldRecording(),
        onPointerUp: (_) => _stopAndUpload(checkMinHold: true),
        onPointerCancel: (_) => _stopAndUpload(checkMinHold: true),
        child: circle,
      ),
    );
  }
}

class _FollowupQuestionCard extends StatelessWidget {
  const _FollowupQuestionCard({
    required this.stepLabel,
    required this.questionText,
    required this.replayLabel,
    required this.reviewLabel,
    required this.canReplay,
    required this.onReplay,
    required this.onSkipToReview,
  });

  final String stepLabel;
  final String questionText;
  final String replayLabel;
  final String reviewLabel;
  final bool canReplay;
  final VoidCallback onReplay;
  final VoidCallback onSkipToReview;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primaryTint,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              stepLabel,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.primaryDark,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            questionText,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: AppColors.inkPrimary,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              TextButton.icon(
                onPressed: canReplay ? onReplay : null,
                icon: const Icon(Icons.volume_up_outlined, size: 18),
                label: Text(replayLabel),
              ),
              const Spacer(),
              TextButton(
                onPressed: onSkipToReview,
                child: Text(reviewLabel),
              ),
            ],
          ),
        ],
      ),
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

class _SavedOfflineCard extends StatelessWidget {
  const _SavedOfflineCard({
    required this.title,
    required this.subtitle,
    required this.buttonLabel,
    required this.onDone,
  });

  final String title;
  final String subtitle;
  final String buttonLabel;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppColors.warningBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.warningBorder),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.cloud_off_rounded,
            size: 44,
            color: AppColors.warningText,
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.warningText,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.inkPrimary,
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onDone,
              child: Text(buttonLabel),
            ),
          ),
        ],
      ),
    );
  }
}

class _VisitConsentCard extends StatelessWidget {
  const _VisitConsentCard({
    required this.title,
    required this.checkboxLabel,
    required this.verbalLabel,
    required this.signedLabel,
    required this.method,
    required this.saving,
    required this.onMethodChanged,
    required this.onConfirmChanged,
  });

  final String title;
  final String checkboxLabel;
  final String verbalLabel;
  final String signedLabel;
  final String method;
  final bool saving;
  final ValueChanged<String> onMethodChanged;
  final ValueChanged<bool?> onConfirmChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: tokens.surfaceRaised,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: tokens.outline,
          width: AppSizes.borderWidth,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                Icons.verified_user_outlined,
                size: AppSizes.icon,
                color: tokens.primary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  title,
                  style: AppTypography.heading(tokens.ink),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              ChoiceChip(
                label: Text(verbalLabel),
                selected: method == 'verbal',
                onSelected: saving ? null : (_) => onMethodChanged('verbal'),
              ),
              ChoiceChip(
                label: Text(signedLabel),
                selected: method == 'signed',
                onSelected: saving ? null : (_) => onMethodChanged('signed'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          CheckboxListTile(
            key: const ValueKey('visit_consent_checkbox'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: false,
            onChanged: saving ? null : onConfirmChanged,
            title: Text(
              checkboxLabel,
              style: AppTypography.body(tokens.ink),
            ),
          ),
        ],
      ),
    );
  }
}
