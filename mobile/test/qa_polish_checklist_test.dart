import 'dart:math' as math;

import 'package:asha_vaani/l10n/app_strings.dart';
import 'package:asha_vaani/models/beneficiary.dart';
import 'package:asha_vaani/models/newborn_visit.dart';
import 'package:asha_vaani/models/v2_models.dart';
import 'package:asha_vaani/screens/add_beneficiary_screen.dart';
import 'package:asha_vaani/screens/beneficiary_list_screen.dart';
import 'package:asha_vaani/screens/beneficiary_profile_screen.dart';
import 'package:asha_vaani/screens/home_dashboard_screen.dart';
import 'package:asha_vaani/screens/insights_screen.dart';
import 'package:asha_vaani/screens/login_screen.dart';
import 'package:asha_vaani/screens/privacy_and_data_screen.dart';
import 'package:asha_vaani/screens/record_visit_screen.dart';
import 'package:asha_vaani/screens/review_confirm_screen.dart';
import 'package:asha_vaani/screens/settings_screen.dart';
import 'package:asha_vaani/screens/visit_purpose_picker_screen.dart';
import 'package:asha_vaani/services/api_client.dart';
import 'package:asha_vaani/theme/app_theme.dart';
import 'package:asha_vaani/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

double _relativeLuminance(Color c) {
  double linearize(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * linearize(c.r) +
      0.7152 * linearize(c.g) +
      0.0722 * linearize(c.b);
}

double _contrastRatio(Color a, Color b) {
  final la = _relativeLuminance(a);
  final lb = _relativeLuminance(b);
  final lighter = math.max(la, lb);
  final darker = math.min(la, lb);
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  test('WCAG 4.5:1 contrast holds for all text and badge token pairs', () {
    for (final entry in <(String, AppTokens)>[
      ('standard', AppTokens.standard),
      ('highContrast', AppTokens.highContrast),
    ]) {
      final t = entry.$2;
      final pairs = <(String, Color, Color)>[
        ('ink/surface', t.ink, t.surface),
        ('ink/surfaceRaised', t.ink, t.surfaceRaised),
        ('inkMuted/surface', t.inkMuted, t.surface),
        ('inkMuted/surfaceRaised', t.inkMuted, t.surfaceRaised),
        ('white/primary', Colors.white, t.primary),
        ('primary/primaryContainer', t.primary, t.primaryContainer),
        ('primary/surface', t.primary, t.surface),
        ('riskHigh/riskHighContainer', t.riskHigh, t.riskHighContainer),
        ('riskHigh/surface', t.riskHigh, t.surface),
        ('white/riskHigh', Colors.white, t.riskHigh),
        ('riskMedium/riskMediumContainer', t.riskMedium, t.riskMediumContainer),
        ('riskMedium/surface', t.riskMedium, t.surface),
        ('riskOk/riskOkContainer', t.riskOk, t.riskOkContainer),
        ('riskOk/surface', t.riskOk, t.surface),
        ('info/infoContainer', t.info, t.infoContainer),
        ('info/surface', t.info, t.surface),
      ];
      for (final p in pairs) {
        expect(
          _contrastRatio(p.$2, p.$3),
          greaterThanOrEqualTo(4.5),
          reason: '${entry.$1} ${p.$1} failed 4.5:1 WCAG contrast',
        );
      }
    }
  });

  testWidgets(
    'All primary V2 screens render without overflow on 360x640 at 130% text scale in Hindi and Kannada',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const sampleBen = Beneficiary(
        id: '1042',
        uuid: 'ben-qa-1',
        label: 'Baby of Sunita',
        beneficiaryType: 'newborn',
        riskLevel: 'high',
        consentRecorded: true,
        phoneMasked: '••••••3210',
        phoneLocal: '9876543210',
      );
      const sampleTurn = VisitTurnResponse(
        sessionId: 'sess-qa',
        transcript: 'Baby weight 2.3 kg, temperature 37.8 C',
        record: NewbornVisitRecord(
          beneficiaryId: ExtractedField(value: '1042', source: 'selected'),
          babyWeightKg: ExtractedField(value: 2.3, confidence: 0.92),
          temperatureC: ExtractedField(value: 37.8, confidence: 0.90),
          riskFlags: ['low_birth_weight'],
          referralSuggested: true,
        ),
        riskFlags: ['low_birth_weight'],
        referralSuggested: true,
        status: 'ready_to_confirm',
      );

      for (final lang in [AppLanguage.hi, AppLanguage.kn]) {
        final fakeApi = FakeAshaApiClient()
          ..beneficiaries = const [sampleBen]
          ..profileVisitsById['1042'] = const BeneficiaryProfileVisits(
            beneficiaryId: '1042',
            visits: [
              VisitSummary(
                visitId: 'v-qa-1',
                sessionId: 's-qa-1',
                beneficiaryId: '1042',
                riskFlags: ['low_birth_weight'],
                referralSuggested: true,
                status: 'saved',
                updatedAt: '2026-11-21T10:00:00Z',
              ),
            ],
          );
        final fakeDb = FakeLocalDbService();
        await fakeDb.upsertBeneficiaryV2(
          BeneficiaryRecord(
            id: 'ben-qa-1',
            localCode: '1042',
            workerId: 'asha_001',
            fullName: 'Baby of Sunita',
            beneficiaryType: 'newborn',
            dob: '2026-11-12',
            riskLevel: 'high',
            nextDueAt: '2026-11-22',
            createdAt: '2026-11-12T08:00:00Z',
            updatedAt: '2026-11-21T10:00:00Z',
          ),
        );
        final appState = makeTestAppState(
          api: fakeApi,
          localDb: fakeDb,
          initialLanguage: lang,
          initialProfile: AshaProfile.defaults.first,
        );
        final refreshSignal = ValueNotifier<int>(0);
        addTearDown(refreshSignal.dispose);

        final screens = <(String, Widget)>[
          ('LoginScreen', LoginScreen(appState: appState)),
          (
            'HomeDashboardScreen',
            Scaffold(
              body: HomeDashboardScreen(
                appState: appState,
                refreshSignal: refreshSignal,
                onSelectTab: (_) {},
                onVisitSaved: () {},
              ),
            ),
          ),
          (
            'BeneficiaryListScreen',
            Scaffold(
              body: BeneficiaryListScreen(
                appState: appState,
                onVisitSaved: () {},
              ),
            ),
          ),
          (
            'AddBeneficiaryScreen',
            AddBeneficiaryScreen(
              appState: appState,
              existingBeneficiaries: const [sampleBen],
            ),
          ),
          (
            'BeneficiaryProfileScreen',
            BeneficiaryProfileScreen(
              appState: appState,
              beneficiary: sampleBen,
            ),
          ),
          (
            'VisitPurposePickerScreen',
            VisitPurposePickerScreen(
              appState: appState,
              beneficiary: sampleBen,
            ),
          ),
          (
            'RecordVisitScreen',
            RecordVisitScreen(
              appState: appState,
              beneficiary: sampleBen,
            ),
          ),
          (
            'ReviewConfirmScreen',
            ReviewConfirmScreen(
              appState: appState,
              initialTurn: sampleTurn,
            ),
          ),
          (
            'InsightsScreen',
            Scaffold(
              body: InsightsScreen(
                appState: appState,
                refreshSignal: refreshSignal,
              ),
            ),
          ),
          (
            'SettingsScreen',
            Scaffold(
              body: SettingsScreen(
                appState: appState,
                refreshSignal: refreshSignal,
              ),
            ),
          ),
          (
            'PrivacyAndDataScreen',
            PrivacyAndDataScreen(appState: appState),
          ),
        ];

        for (final entry in screens) {
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.lightTheme(),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: const TextScaler.linear(1.3),
                ),
                child: child!,
              ),
              home: entry.$2,
            ),
          );
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: '${entry.$1} (${lang.code}) threw on 360x640 @ 130%',
          );
        }
      }
    },
  );

  testWidgets(
    'RecordVisitScreen exposes TalkBack semantics and >= 48dp touch targets',
    (tester) async {
      final semanticsHandle = tester.ensureSemantics();
      try {
        final appState = makeTestAppState(
          api: FakeAshaApiClient(),
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

        final micFinder = find.byKey(const ValueKey('push_to_talk_button'));
        final autoDetectFinder =
            find.byKey(const ValueKey('auto_detect_language_toggle'));
        expect(micFinder, findsOneWidget);
        expect(autoDetectFinder, findsOneWidget);

        final micSize = tester.getSize(micFinder);
        final chipSize = tester.getSize(autoDetectFinder);
        expect(micSize.width, greaterThanOrEqualTo(48));
        expect(micSize.height, greaterThanOrEqualTo(48));
        expect(chipSize.height, greaterThanOrEqualTo(48));

        final micSemanticsFinder = find.ancestor(
          of: micFinder,
          matching: find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.label == 'Hold to Speak',
          ),
        );
        expect(micSemanticsFinder, findsOneWidget);
        final micSemantics = tester.getSemantics(micSemanticsFinder);
        expect(micSemantics.label, contains('Hold to Speak'));
      } finally {
        semanticsHandle.dispose();
      }
    },
  );

  testWidgets(
    'Airplane-mode workflow: create beneficiary locally, record offline visit, then sync on reconnect',
    (tester) async {
      final fakeApi = FakeAshaApiClient()
        ..uploadError = const ApiException('NETWORK_ERROR', 'Offline');
      final fakeDb = FakeLocalDbService();
      final fakeConn = FakeConnectivityMonitor(initialOnline: false);
      final appState = makeTestAppState(
        api: fakeApi,
        localDb: fakeDb,
        connectivity: fakeConn,
        initialLanguage: AppLanguage.en,
        initialProfile: AshaProfile.defaults.first,
      );
      await appState.syncService.start();

      // Add a beneficiary locally while offline
      await fakeDb.upsertBeneficiaryV2(
        BeneficiaryRecord(
          id: 'ben-offline-1',
          localCode: '2040',
          workerId: 'asha_001',
          fullName: 'Kavita Offline',
          beneficiaryType: 'newborn',
          dob: '2026-11-18',
          createdAt: '2026-11-21T08:00:00Z',
          updatedAt: '2026-11-21T08:00:00Z',
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme(),
          home: RecordVisitScreen(
            appState: appState,
            beneficiary: const Beneficiary(
              id: '2040',
              uuid: 'ben-offline-1',
              label: 'Kavita Offline',
              consentRecorded: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final mic = find.byKey(const ValueKey('push_to_talk_button'));
      final gesture = await tester.startGesture(tester.getCenter(mic));
      await tester.pump(const Duration(milliseconds: 650));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.text('Saved offline'), findsOneWidget);
      expect(appState.syncService.pendingCount, 1);

      // Reconnect and sync queued items
      fakeApi.uploadError = null;
      fakeConn.emitOnline(true);
      await tester.pumpAndSettle();
      if (appState.syncService.pendingCount > 0) {
        await appState.syncService.syncPending();
        await tester.pumpAndSettle();
      }
      expect(appState.syncService.pendingCount, 0);
      expect(fakeApi.syncCalls, isNotEmpty);
    },
  );

  testWidgets(
    'Confirmed visits are immutable and amendments remain visible in BeneficiaryProfileScreen history',
    (tester) async {
      final fakeDb = FakeLocalDbService();
      await fakeDb.upsertBeneficiaryV2(
        BeneficiaryRecord(
          id: 'ben-amend-1',
          localCode: '1042',
          workerId: 'asha_001',
          fullName: 'Baby of Sunita',
          beneficiaryType: 'newborn',
          dob: '2026-11-10',
          createdAt: '2026-11-10T08:00:00Z',
          updatedAt: '2026-11-20T08:00:00Z',
        ),
      );
      final visit = VisitRecord(
        id: 'visit-imm-1',
        beneficiaryId: 'ben-amend-1',
        workerId: 'asha_001',
        visitedAt: '2026-11-20T10:00:00Z',
        status: 'draft',
        payload: {'baby_weight_kg': 2.3},
        updatedAt: '2026-11-20T10:00:00Z',
      );
      await fakeDb.confirmVisitV2(visit, actorId: 'asha_001');

      await expectLater(
        fakeDb.confirmVisitV2(visit, actorId: 'asha_001'),
        throwsA(isA<VisitImmutableException>()),
      );

      await fakeDb.amendVisitV2(
        visitId: 'visit-imm-1',
        changedBy: 'asha_001',
        changes: {'baby_weight_kg': 2.5},
        reason: 'Corrected scale reading',
      );

      final fakeApi = FakeAshaApiClient()
        ..profileVisitsById['ben-amend-1'] = const BeneficiaryProfileVisits(
          beneficiaryId: 'ben-amend-1',
          visits: [
            VisitSummary(
              visitId: 'visit-imm-1',
              sessionId: 'sess-imm-1',
              beneficiaryId: '1042',
              ashaId: 'Lakshmi Devi',
              visitDate: '2026-11-20',
              status: 'amended',
              updatedAt: '2026-11-20T10:00:00Z',
            ),
          ],
        );

      final appState = makeTestAppState(
        api: fakeApi,
        localDb: fakeDb,
        initialLanguage: AppLanguage.en,
        initialProfile: AshaProfile.defaults.first,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme(),
          home: BeneficiaryProfileScreen(
            appState: appState,
            beneficiary: const Beneficiary(
              id: '1042',
              uuid: 'ben-amend-1',
              label: 'Baby of Sunita',
              beneficiaryType: 'newborn',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Amended (1)'), findsOneWidget);
    },
  );
}
