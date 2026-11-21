import 'dart:typed_data';

import 'package:asha_vaani/l10n/app_strings.dart';
import 'package:asha_vaani/models/beneficiary.dart';
import 'package:asha_vaani/models/newborn_visit.dart';
import 'package:asha_vaani/screens/record_visit_screen.dart';
import 'package:asha_vaani/screens/review_confirm_screen.dart';
import 'package:asha_vaani/services/visit_stream_client.dart';
import 'package:asha_vaani/services/wav_encoder.dart';
import 'package:asha_vaani/theme/app_theme.dart';
import 'package:asha_vaani/ui/live_transcript.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

Uint8List _pcmSampleChunk({int sampleValue = 4000, int samples = 512}) {
  final bytes = Uint8List(samples * 2);
  final view = ByteData.sublistView(bytes);
  for (var i = 0; i < samples; i++) {
    view.setInt16(i * 2, sampleValue, Endian.little);
  }
  return bytes;
}

void main() {
  test(
    'WavEncoder writes valid 16 kHz PCM16 mono RIFF/WAVE header and computes audio level',
    () {
      final silence = Uint8List(1024);
      expect(WavEncoder.computeAudioLevel(silence), 0.0);

      final loudPcm = _pcmSampleChunk(sampleValue: 6000, samples: 512);
      expect(WavEncoder.computeAudioLevel(loudPcm), closeTo(0.5, 0.01));

      final wav = WavEncoder.encodePcm16Mono(loudPcm, sampleRate: 16000);
      expect(wav.length, 44 + loudPcm.length);
      expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
      expect(String.fromCharCodes(wav.sublist(12, 16)), 'fmt ');
      expect(String.fromCharCodes(wav.sublist(36, 40)), 'data');

      final bd = ByteData.sublistView(wav);
      expect(bd.getUint32(4, Endian.little), 36 + loudPcm.length);
      expect(bd.getUint32(24, Endian.little), 16000);
      expect(bd.getUint32(28, Endian.little), 32000);
      expect(bd.getUint16(34, Endian.little), 16);
      expect(bd.getUint32(40, Endian.little), loudPcm.length);

      expect(
        IoVisitStreamClient.buildStreamUri('http://10.0.2.2:8000').toString(),
        'ws://10.0.2.2:8000/v1/stream',
      );
      expect(
        IoVisitStreamClient.buildStreamUri('https://api.ashavaani.in/').toString(),
        'wss://api.ashavaani.in/v1/stream',
      );
    },
  );

  testWidgets(
    'RecordVisitScreen streams PCM chunks, shows LiveTranscript captions, toggles auto-detect, and navigates without batch upload',
    (tester) async {
      final api = FakeAshaApiClient();
      final recorder = FakeAudioCaptureService()..supportsStreaming = true;
      final streamClient = FakeVisitStreamClient();
      final appState = makeTestAppState(
        api: api,
        recorder: recorder,
        visitStreamClient: streamClient,
        initialLanguage: AppLanguage.en,
        initialProfile: AshaProfile.defaults.first,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme(),
          home: RecordVisitScreen(
            appState: appState,
            beneficiary: const Beneficiary(
              id: '1042',
              label: 'Baby of Sunita',
              consentRecorded: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Enable Auto-detect language before speaking
      await tester.tap(find.byKey(const ValueKey('auto_detect_language_toggle')));
      await tester.pumpAndSettle();

      final mic = find.byKey(const ValueKey('push_to_talk_button'));
      final gesture = await tester.startGesture(tester.getCenter(mic));
      await tester.pump(const Duration(milliseconds: 650));

      expect(streamClient.lastLanguage, 'auto');
      expect(streamClient.sessions, hasLength(1));
      final session = streamClient.sessions.first;

      session.onStop = () {
        session.emitEvent(
          const StreamServerEvent(
            type: StreamEventType.fields,
            sessionId: 'stream-sess-1',
            text: 'Baby weight 2.3 kg',
            status: 'ready_to_confirm',
            record: NewbornVisitRecord(
              beneficiaryId: ExtractedField(value: '1042', source: 'selected'),
              babyWeightKg: ExtractedField(value: 2.3),
              temperatureC: ExtractedField(value: 36.8),
            ),
            riskFlags: ['low_birth_weight'],
          ),
        );
      };

      recorder.streamController!.add(_pcmSampleChunk());
      await tester.pump();
      expect(session.sentPcmChunks, isNotEmpty);

      session.emitEvent(
        const StreamServerEvent(
          type: StreamEventType.partial,
          text: 'Baby weight',
        ),
      );
      await tester.pump();
      expect(find.byType(LiveTranscript), findsOneWidget);
      expect(find.textContaining('Baby weight'), findsWidgets);

      session.emitEvent(
        const StreamServerEvent(
          type: StreamEventType.finalText,
          text: 'Baby weight 2.3 kg',
          utteranceId: 1,
        ),
      );
      await tester.pump();
      expect(find.textContaining('2.3'), findsWidgets);

      await gesture.up();
      await tester.pumpAndSettle();

      expect(session.stopped, isTrue);
      expect(api.uploadCalls, isEmpty);
      expect(find.byType(ReviewConfirmScreen), findsOneWidget);
    },
  );

  testWidgets(
    'RecordVisitScreen shows paused notice on mid-stream drop and falls back to local WAV batch upload',
    (tester) async {
      final api = FakeAshaApiClient()
        ..nextUploadResponse = const VisitTurnResponse(
          sessionId: 'batch-fallback-1',
          transcript: 'Fallback weight 2.6 kg',
          record: NewbornVisitRecord(
            beneficiaryId: ExtractedField(value: '1042', source: 'selected'),
            babyWeightKg: ExtractedField(value: 2.6),
          ),
          status: 'ready_to_confirm',
        );
      final recorder = FakeAudioCaptureService()..supportsStreaming = true;
      final streamClient = FakeVisitStreamClient();
      final appState = makeTestAppState(
        api: api,
        recorder: recorder,
        visitStreamClient: streamClient,
        initialLanguage: AppLanguage.en,
        initialProfile: AshaProfile.defaults.first,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme(),
          home: RecordVisitScreen(
            appState: appState,
            beneficiary: const Beneficiary(
              id: '1042',
              label: 'Baby of Sunita',
              consentRecorded: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final mic = find.byKey(const ValueKey('push_to_talk_button'));
      final gesture = await tester.startGesture(tester.getCenter(mic));
      await tester.pump(const Duration(milliseconds: 650));

      recorder.streamController!.add(_pcmSampleChunk(samples: 1024));
      await tester.pump();

      // Simulate stream dropping mid-recording
      streamClient.sessions.first.emitEvent(
        const StreamServerEvent(
          type: StreamEventType.error,
          errorCode: 'STT_STREAM_FAILED',
          errorMessage: 'WebSocket disconnected',
        ),
      );
      await tester.pump();
      expect(find.text('Live captions paused, still recording'), findsOneWidget);

      await gesture.up();
      await tester.pumpAndSettle();

      expect(api.uploadCalls, hasLength(1));
      expect(find.byType(ReviewConfirmScreen), findsOneWidget);
    },
  );

  testWidgets(
    'RecordVisitScreen with LiveTranscript and paused notice renders cleanly on 360x640 at 130% text scale',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final api = FakeAshaApiClient();
      final recorder = FakeAudioCaptureService()..supportsStreaming = true;
      final streamClient = FakeVisitStreamClient();
      final appState = makeTestAppState(
        api: api,
        recorder: recorder,
        visitStreamClient: streamClient,
        initialLanguage: AppLanguage.en,
        initialProfile: AshaProfile.defaults.first,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(1.3),
            ),
            child: child!,
          ),
          home: RecordVisitScreen(
            appState: appState,
            beneficiary: const Beneficiary(
              id: '1042',
              label: 'Baby of Sunita',
              consentRecorded: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final mic = find.byKey(const ValueKey('push_to_talk_button'));
      await tester.ensureVisible(mic);
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(tester.getCenter(mic));
      await tester.pump(const Duration(milliseconds: 650));

      streamClient.sessions.first.emitEvent(
        const StreamServerEvent(
          type: StreamEventType.finalText,
          text: 'Weight 2.4 kg and temperature 37.1',
          utteranceId: 1,
        ),
      );
      streamClient.sessions.first.emitEvent(
        const StreamServerEvent(
          type: StreamEventType.error,
          errorCode: 'STT_STREAM_FAILED',
          errorMessage: 'Network drop',
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);

      streamClient.sessions.first.onStop = null;
      await gesture.cancel();
      await tester.pumpAndSettle();
    },
  );
}
