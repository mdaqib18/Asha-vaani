import 'package:asha_vaani/l10n/app_strings.dart';
import 'package:asha_vaani/models/beneficiary.dart';
import 'package:asha_vaani/models/newborn_visit.dart';
import 'package:asha_vaani/screens/review_confirm_screen.dart';
import 'package:asha_vaani/state/app_state.dart';
import 'package:asha_vaani/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  testWidgets('highlights flagged fields, shows referral banner, patches edit, and confirms',
      (tester) async {
    final fakeApi = FakeAshaApiClient();
    final appState = AppState(
      apiClient: fakeApi,
      recorder: FakeAudioCaptureService(),
      initialLanguage: AppLanguage.en,
      initialProfile: AshaProfile.defaults.first,
    );

    final initialTurn = VisitTurnResponse(
      sessionId: 'sess-99',
      transcript: 'Beneficiary 1042 weight 2.2 kg',
      record: const NewbornVisitRecord(
        beneficiaryId: ExtractedField(value: '1042', source: 'selected'),
        babyWeightKg: ExtractedField(
          value: 2.2,
          confidence: 0.7,
          source: 'speech',
          needsConfirmation: true,
        ),
        riskFlags: ['low_birth_weight'],
        referralSuggested: true,
      ),
      flags: const [
        ValidationFlag(field: 'temperature_c', reason: 'missing_required'),
      ],
      riskFlags: const ['low_birth_weight'],
      referralSuggested: true,
      status: 'needs_followup',
      followup: const FollowupPayload(
        questionText: 'Temperature details are missing.',
        targetFields: ['temperature_c'],
        followupCount: 1,
      ),
    );

    fakeApi.nextPatchResponse = const RecordPatchResponse(
      sessionId: 'sess-99',
      record: NewbornVisitRecord(
        beneficiaryId: ExtractedField(value: '1042', source: 'selected'),
        babyWeightKg: ExtractedField(
          value: 2.8,
          confidence: 1.0,
          source: 'typed',
          needsConfirmation: false,
        ),
      ),
      flags: [ValidationFlag(field: 'temperature_c', reason: 'missing_required')],
      riskFlags: [],
      referralSuggested: false,
      status: 'needs_followup',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme(),
        home: ReviewConfirmScreen(appState: appState, initialTurn: initialTurn),
      ),
    );
    await tester.pumpAndSettle();

    // Neutral referral banner and low birth weight chip shown
    expect(find.text('Suggest consulting ANM/doctor'), findsOneWidget);
    expect(find.text('Low weight (<2.5 kg)'), findsOneWidget);

    // Highlighted verify/missing badges rendered
    expect(find.text('Verify'), findsOneWidget);
    expect(find.text('Missing'), findsWidgets);

    // Tap baby_weight_kg card, edit to 2.8, and save
    await tester.tap(find.byKey(const ValueKey('field_card_baby_weight_kg')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '2.8');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(fakeApi.patchCalls.length, 1);
    expect(fakeApi.patchCalls.first['fields'], {'baby_weight_kg': 2.8});
    expect(find.text('2.8 kg'), findsOneWidget);
    expect(find.text('Suggest consulting ANM/doctor'), findsNothing);

    // Tap Confirm & Save
    await tester.tap(find.text('Confirm & Save'));
    await tester.pumpAndSettle();
    expect(fakeApi.confirmCalls, ['sess-99']);
  });
}
