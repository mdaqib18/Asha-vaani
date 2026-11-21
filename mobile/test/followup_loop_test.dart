import 'package:asha_vaani/l10n/app_strings.dart';
import 'package:asha_vaani/models/beneficiary.dart';
import 'package:asha_vaani/models/newborn_visit.dart';
import 'package:asha_vaani/screens/record_visit_screen.dart';
import 'package:asha_vaani/screens/review_confirm_screen.dart';
import 'package:asha_vaani/state/app_state.dart';
import 'package:asha_vaani/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  testWidgets('plays follow-up TTS, auto-opens mic, submits answers, and navigates on ready_to_confirm',
      (tester) async {
    final fakeApi = FakeAshaApiClient();
    final fakeRecorder = FakeAudioCaptureService();
    final fakePlayer = FakeAudioPlaybackService();
    final appState = AppState(
      apiClient: fakeApi,
      recorder: fakeRecorder,
      audioPlayer: fakePlayer,
      initialLanguage: AppLanguage.en,
      initialProfile: AshaProfile.defaults.first,
    );

    fakeApi.nextUploadResponse = const VisitTurnResponse(
      sessionId: 'sess-1',
      transcript: 'Beneficiary 1042 weight 2.5 kg limb problem',
      record: NewbornVisitRecord(
        beneficiaryId: ExtractedField(value: '1042', source: 'selected'),
        babyWeightKg: ExtractedField(value: 2.5),
      ),
      status: 'needs_followup',
      followup: FollowupPayload(
        questionText: 'Temperature and feeding details are missing.',
        questionAudioUrl: '/v1/audio/q1',
        targetFields: ['temperature_c', 'breastfeeding'],
        followupCount: 1,
      ),
    );

    fakeApi.followupResponses.addAll([
      const VisitTurnResponse(
        sessionId: 'sess-1',
        transcript: 'Temperature 37, breastfeeding exclusive',
        record: NewbornVisitRecord(
          beneficiaryId: ExtractedField(value: '1042', source: 'selected'),
          babyWeightKg: ExtractedField(value: 2.5),
          temperatureC: ExtractedField(value: 37.0),
          breastfeeding: ExtractedField(value: 'exclusive'),
        ),
        status: 'needs_followup',
        followup: FollowupPayload(
          questionText: 'Which limb is affected?',
          questionAudioUrl: '/v1/audio/q2',
          targetFields: ['limb_abnormality.location'],
          followupCount: 2,
        ),
      ),
      const VisitTurnResponse(
        sessionId: 'sess-1',
        transcript: 'Left leg',
        record: NewbornVisitRecord(
          beneficiaryId: ExtractedField(value: '1042', source: 'selected'),
          babyWeightKg: ExtractedField(value: 2.5),
          temperatureC: ExtractedField(value: 37.0),
          breastfeeding: ExtractedField(value: 'exclusive'),
          limbAbnormality: ExtractedField(
            value: LimbAbnormality(present: true, location: 'left_leg'),
          ),
        ),
        status: 'ready_to_confirm',
        followup: null,
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme(),
        home: RecordVisitScreen(
          appState: appState,
          beneficiary: const Beneficiary(id: '1042', label: 'Baby of Sunita (synthetic)'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Hold push-to-talk for >500ms and release for initial audio
    final micFinder = find.byKey(const ValueKey('push_to_talk_button'));
    final gesture = await tester.startGesture(tester.getCenter(micFinder));
    await tester.pump(const Duration(milliseconds: 650));
    await gesture.up();
    await tester.pumpAndSettle();

    // Turn 1 follow-up played q1 and auto-opened mic
    expect(fakePlayer.playedUrls, ['http://10.0.2.2:8000/v1/audio/q1']);
    expect(fakeRecorder.startCalls, 2);
    expect(find.text('Follow-up 1 of 2'), findsOneWidget);
    expect(find.text('Temperature and feeding details are missing.'), findsOneWidget);
    expect(find.byKey(const ValueKey('stop_followup_button')), findsOneWidget);

    // Tap Stop to submit follow-up 1 answer -> triggers follow-up 2
    await tester.tap(find.byKey(const ValueKey('stop_followup_button')));
    await tester.pumpAndSettle();

    expect(fakeApi.answerCalls.length, 1);
    expect(fakePlayer.playedUrls, [
      'http://10.0.2.2:8000/v1/audio/q1',
      'http://10.0.2.2:8000/v1/audio/q2',
    ]);
    expect(fakeRecorder.startCalls, 3);
    expect(find.text('Follow-up 2 of 2'), findsOneWidget);
    expect(find.text('Which limb is affected?'), findsOneWidget);

    // Tap Stop to submit follow-up 2 answer -> navigates to ReviewConfirmScreen
    await tester.tap(find.byKey(const ValueKey('stop_followup_button')));
    await tester.pumpAndSettle();

    expect(fakeApi.answerCalls.length, 2);
    expect(find.byType(ReviewConfirmScreen), findsOneWidget);
    expect(find.text('37.0 °C'), findsOneWidget);
  });

  testWidgets('skipToReview exits follow-up loop directly to ReviewConfirmScreen',
      (tester) async {
    final fakeApi = FakeAshaApiClient();
    final fakeRecorder = FakeAudioCaptureService();
    final fakePlayer = FakeAudioPlaybackService();
    final appState = AppState(
      apiClient: fakeApi,
      recorder: fakeRecorder,
      audioPlayer: fakePlayer,
      initialLanguage: AppLanguage.en,
      initialProfile: AshaProfile.defaults.first,
    );

    fakeApi.nextUploadResponse = const VisitTurnResponse(
      sessionId: 'sess-2',
      transcript: 'Beneficiary 1042 weight 2.5 kg',
      record: NewbornVisitRecord(
        beneficiaryId: ExtractedField(value: '1042', source: 'selected'),
        babyWeightKg: ExtractedField(value: 2.5),
      ),
      status: 'needs_followup',
      followup: FollowupPayload(
        questionText: 'Temperature details are missing.',
        questionAudioUrl: '/v1/audio/q1',
        targetFields: ['temperature_c'],
        followupCount: 1,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme(),
        home: RecordVisitScreen(
          appState: appState,
          beneficiary: const Beneficiary(id: '1042', label: 'Baby of Sunita (synthetic)'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('push_to_talk_button'))),
    );
    await tester.pump(const Duration(milliseconds: 650));
    await gesture.up();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Review now'));
    await tester.pumpAndSettle();

    expect(find.byType(ReviewConfirmScreen), findsOneWidget);
  });

  testWidgets('ReviewConfirmScreen Read Back plays TTS readback audio URL',
      (tester) async {
    final fakeApi = FakeAshaApiClient();
    final fakePlayer = FakeAudioPlaybackService();
    final appState = AppState(
      apiClient: fakeApi,
      recorder: FakeAudioCaptureService(),
      audioPlayer: fakePlayer,
      initialLanguage: AppLanguage.en,
      initialProfile: AshaProfile.defaults.first,
    );

    const turn = VisitTurnResponse(
      sessionId: 'sess-3',
      transcript: 'weight 2.5 kg',
      record: NewbornVisitRecord(
        beneficiaryId: ExtractedField(value: '1042', source: 'selected'),
        babyWeightKg: ExtractedField(value: 2.5),
      ),
      status: 'ready_to_confirm',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme(),
        home: ReviewConfirmScreen(appState: appState, initialTurn: turn),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Read Back'));
    await tester.pumpAndSettle();

    expect(find.text(fakeApi.readbackResponse.text), findsOneWidget);
    expect(fakePlayer.playedUrls, ['http://10.0.2.2:8000/v1/audio/readback-1']);
  });
}
