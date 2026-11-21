import 'package:asha_vaani/l10n/app_strings.dart';
import 'package:asha_vaani/models/newborn_visit.dart';
import 'package:asha_vaani/screens/login_screen.dart';
import 'package:asha_vaani/screens/supervisor_flagged_screen.dart';
import 'package:asha_vaani/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  testWidgets(
      'supervisor view opens from login, lists flagged cases, and shows detail sheet',
      (tester) async {
    final fakeApi = FakeAshaApiClient()
      ..flaggedVisits = const [
        VisitSummary(
          visitId: 'v-1',
          sessionId: 'sess-flagged-1',
          ashaId: 'asha_002',
          beneficiaryId: '2011',
          visitDate: '2026-11-21',
          riskFlags: ['low_birth_weight', 'fever'],
          referralSuggested: true,
          status: 'saved',
          updatedAt: '2026-11-21T10:00:00Z',
        ),
      ]
      ..visitDetailsBySession['sess-flagged-1'] = const VisitDetail(
        sessionId: 'sess-flagged-1',
        visitId: 'v-1',
        ashaId: 'asha_002',
        status: 'saved',
        record: NewbornVisitRecord(
          beneficiaryId: ExtractedField(value: '2011', source: 'selected'),
          babyWeightKg: ExtractedField(value: 2.2),
          temperatureC: ExtractedField(value: 37.8),
          breastfeeding: ExtractedField(value: 'exclusive'),
          cordStatus: ExtractedField(value: 'clean_dry'),
          jaundice: ExtractedField(value: false),
          riskFlags: ['low_birth_weight', 'fever'],
          referralSuggested: true,
        ),
        lastTranscript: 'Beneficiary 2011 weight 2.2 kg temperature 37.8 C',
      );

    final appState = makeTestAppState(
      api: fakeApi,
      initialLanguage: AppLanguage.en,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme(),
        home: LoginScreen(appState: appState),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Voice consent required · Synthetic demo data only'),
      findsOneWidget,
    );
    expect(find.text('ANM / Supervisor View'), findsOneWidget);

    await tester.tap(find.text('ANM / Supervisor View'));
    await tester.pumpAndSettle();

    expect(find.text('Flagged Cases (ANM)'), findsOneWidget);
    expect(find.text('1 flagged visit(s)'), findsOneWidget);
    expect(find.text('Suggest consulting ANM/doctor'), findsOneWidget);
    expect(find.text('ASHA: asha_002'), findsOneWidget);
    expect(find.text('Low weight (<2.5 kg)'), findsOneWidget);
    expect(find.text('High temp'), findsOneWidget);

    await tester.tap(find.text('Beneficiary ID: 2011'));
    await tester.pumpAndSettle();

    expect(find.text('Visit Details'), findsOneWidget);
    expect(find.text('2.2 kg'), findsOneWidget);
    expect(find.text('37.8 °C'), findsOneWidget);
  });

  testWidgets('supervisor view shows empty state when no flagged cases exist',
      (tester) async {
    final appState = makeTestAppState(
      api: FakeAshaApiClient()..flaggedVisits = const [],
      initialLanguage: AppLanguage.en,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme(),
        home: SupervisorFlaggedScreen(appState: appState),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No flagged visits right now'), findsOneWidget);
  });
}
