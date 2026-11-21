import 'package:asha_vaani/l10n/app_strings.dart';
import 'package:asha_vaani/models/beneficiary.dart';
import 'package:asha_vaani/models/visit_type.dart';
import 'package:asha_vaani/screens/record_visit_screen.dart';
import 'package:asha_vaani/screens/visit_purpose_picker_screen.dart';
import 'package:asha_vaani/services/api_client.dart';
import 'package:asha_vaani/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  test('BuiltInVisitTypes suggests schedule-aware purposes and detects speech keywords', () {
    final today = DateTime.utc(2026, 11, 22);
    final newborn = BuiltInVisitTypes.suggestForBeneficiary(
      beneficiaryId: '1042',
      beneficiaryType: 'newborn',
      dobIso: '2026-11-16',
      today: today,
    );
    expect(newborn.suggestedCode, 'newborn_home_visit');
    expect(newborn.localizedReason(AppLanguage.en), contains('day 7'));

    final preg = BuiltInVisitTypes.suggestForBeneficiary(
      beneficiaryId: '2001',
      beneficiaryType: 'pregnant_woman',
      today: today,
    );
    expect(preg.suggestedCode, 'anc_visit');

    final detected = BuiltInVisitTypes.detectFromSpeech('Please do BP check today');
    expect(detected?.code, 'ncd_screening');
  });

  testWidgets(
    'VisitPurposePickerScreen renders suggestion, requires confirmation on speech match, and survives 360x640 at 130% text scale',
    (tester) async {
      final fakeApi = FakeAshaApiClient();
      final appState = makeTestAppState(
        api: fakeApi,
        initialLanguage: AppLanguage.en,
        initialProfile: AshaProfile.defaults.first,
      );

      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(1.3),
            ),
            child: child!,
          ),
          home: VisitPurposePickerScreen(
            appState: appState,
            beneficiary: const Beneficiary(
              id: '1042',
              label: 'Baby of Sunita (synthetic)',
            ),
            beneficiaryType: 'newborn',
            dobIso: DateTime.now()
                .subtract(const Duration(days: 6))
                .toIso8601String()
                .substring(0, 10),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      expect(find.text('Suggested visit'), findsOneWidget);
      expect(find.text('Newborn home visit'), findsOneWidget);

      final listScrollable = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(
        find.text('General illness check'),
        150,
        scrollable: listScrollable,
      );
      expect(find.text('General illness check'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Typing a spoken hint shows confirmation banner instead of auto-switching silently
      final hintFinder = find.byKey(const ValueKey('purpose_voice_hint_input'));
      await tester.ensureVisible(hintFinder);
      await tester.pumpAndSettle();
      await tester.enterText(hintFinder, 'BP check');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      expect(
        find.byKey(const ValueKey('detected_purpose_confirmation')),
        findsOneWidget,
      );
      expect(find.byType(RecordVisitScreen), findsNothing);

      // Confirming the detected chip opens RecordVisitScreen with ncd_screening
      final useDetected = find.text('Use NCD screening (BP & Sugar)');
      await tester.ensureVisible(useDetected);
      await tester.pumpAndSettle();
      await tester.tap(useDetected);
      await tester.pumpAndSettle();
      expect(find.byType(RecordVisitScreen), findsOneWidget);
      final recWidget = tester.widget<RecordVisitScreen>(
        find.byType(RecordVisitScreen),
      );
      expect(recWidget.visitTypeCode, 'ncd_screening');
    },
  );

  testWidgets('VisitPurposePickerScreen falls back offline when API is unreachable', (tester) async {
    final fakeApi = FakeAshaApiClient()
      ..visitTypesError = const ApiException('NETWORK_ERROR')
      ..suggestedPurposeError = const ApiException('NETWORK_ERROR');
    final appState = makeTestAppState(
      api: fakeApi,
      initialLanguage: AppLanguage.en,
      initialProfile: AshaProfile.defaults.first,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme(),
        home: VisitPurposePickerScreen(
          appState: appState,
          beneficiary: const Beneficiary(
            id: '1043',
            label: 'Baby of Kavita (synthetic)',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Offline mode — showing built-in visit types'), findsOneWidget);
    expect(find.text('Newborn home visit'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.byType(RecordVisitScreen), findsOneWidget);
  });
}
