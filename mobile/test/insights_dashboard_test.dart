import 'package:asha_vaani/l10n/app_strings.dart';
import 'package:asha_vaani/models/v2_models.dart';
import 'package:asha_vaani/screens/insights_screen.dart';
import 'package:asha_vaani/services/local_stats_engine.dart';
import 'package:asha_vaani/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  test(
    'LocalStatsEngine computes SPEC_V2 metrics and enforces baseline honesty rule',
    () async {
      final db = FakeLocalDbService();
      final strings = AppStrings.of(AppLanguage.en);
      final today = DateTime.utc(2026, 11, 22);

      await db.upsertBeneficiaryV2(
        BeneficiaryRecord(
          id: 'real_ben_1',
          localCode: '1042',
          workerId: 'asha_001',
          fullName: 'Asha Real Baby',
          beneficiaryType: 'newborn',
          nextDueAt: '2026-11-22',
          createdAt: '2026-11-20T10:00:00Z',
          updatedAt: '2026-11-20T10:00:00Z',
        ),
      );
      await db.confirmVisitV2(
        VisitRecord(
          id: 'real_visit_1',
          beneficiaryId: 'real_ben_1',
          workerId: 'asha_001',
          visitTypeCode: 'newborn_home_visit',
          visitedAt: '2026-11-22',
          payload: const {'weight_kg': 2.2},
          riskFlags: const ['low_birth_weight'],
          referralSuggested: true,
          inputMethod: 'voice',
          startedAt: '2026-11-22T10:00:00Z',
          confirmedAt: '2026-11-22T10:00:40Z',
          updatedAt: '2026-11-22T10:00:40Z',
        ),
      );

      final withoutBaseline = await LocalStatsEngine.compute(
        localDb: db,
        workerId: 'asha_001',
        period: StatsPeriod.sevenDays,
        strings: strings,
        language: AppLanguage.en,
        today: today,
      );
      expect(withoutBaseline.visitsDone, 1);
      expect(withoutBaseline.coverage, closeTo(1.0, 0.001));
      expect(withoutBaseline.highRiskOpen, 1);
      expect(withoutBaseline.referralsSuggested, 1);
      expect(withoutBaseline.avgRecordSeconds, closeTo(40.0, 0.01));
      expect(withoutBaseline.hasDemoData, isFalse);
      expect(withoutBaseline.estimatedMinutesSavedPerVisit, isNull);
      expect(withoutBaseline.estimatedMinutesSavedTotal, isNull);

      final withBaseline = await LocalStatsEngine.compute(
        localDb: db,
        workerId: 'asha_001',
        period: StatsPeriod.sevenDays,
        strings: strings,
        language: AppLanguage.en,
        paperBaselineMinutes: 5.0,
        today: today,
      );
      expect(
        withBaseline.estimatedMinutesSavedPerVisit,
        closeTo(5.0 - 40.0 / 60.0, 0.01),
      );
      expect(
        withBaseline.estimatedMinutesSavedTotal,
        closeTo(5.0 - 40.0 / 60.0, 0.01),
      );
    },
  );

  testWidgets(
    'InsightsScreen switches periods, loads/clears demo data, and reveals Est. time saved only when baseline set',
    (tester) async {
      final api = FakeAshaApiClient();
      final db = FakeLocalDbService();
      final appState = makeTestAppState(api: api, localDb: db);
      final refreshSignal = ValueNotifier<int>(0);
      addTearDown(refreshSignal.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme(),
          home: Scaffold(
            body: InsightsScreen(
              appState: appState,
              refreshSignal: refreshSignal,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Confirmed visits'), findsOneWidget);
      expect(find.text('Demo data'), findsNothing);
      expect(find.text('Est. time saved'), findsNothing);

      await tester.scrollUntilVisible(
        find.text('Load demo data'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Load demo data'));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Demo data'),
        -300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(find.text('Demo data'), findsOneWidget);
      expect(find.text('Est. time saved'), findsNothing);

      // Default 7d window has 6 confirmed visits
      expect(find.text('6'), findsWidgets);

      await tester.tap(find.text('Today'));
      await tester.pumpAndSettle();
      expect(find.text('2'), findsWidgets);

      await tester.tap(find.text('30 days'));
      await tester.pumpAndSettle();
      expect(find.text('9'), findsWidgets);

      // Honesty toggle: setting baseline unlocks Est. time saved
      await appState.setPaperBaselineMinutes(5.0);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Est. time saved'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Est. time saved'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Clear demo data'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Clear demo data'));
      await tester.pumpAndSettle();
      expect(find.text('Demo data'), findsNothing);
    },
  );

  testWidgets(
    'InsightsScreen renders cleanly without overflow on 360x640 at 130% text scale',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final api = FakeAshaApiClient();
      final db = FakeLocalDbService();
      await LocalStatsEngine.seedDemoData(db, workerId: 'asha_001');
      final appState = makeTestAppState(
        api: api,
        localDb: db,
        initialPaperBaselineMinutes: 6.0,
      );
      final refreshSignal = ValueNotifier<int>(0);
      addTearDown(refreshSignal.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(1.3),
            ),
            child: child!,
          ),
          home: Scaffold(
            body: InsightsScreen(
              appState: appState,
              refreshSignal: refreshSignal,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.scrollUntilVisible(
        find.text('Clear demo data'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
