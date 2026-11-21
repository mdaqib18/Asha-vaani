import 'package:asha_vaani/l10n/app_strings.dart';
import 'package:asha_vaani/main.dart';
import 'package:asha_vaani/models/beneficiary.dart';
import 'package:asha_vaani/models/newborn_visit.dart';
import 'package:asha_vaani/services/api_client.dart';
import 'package:asha_vaani/services/pin_hasher.dart';
import 'package:asha_vaani/ui/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  test('PinHasher matches reference SHA-256 vector and verifies PIN safely', () {
    const expected =
        '351cee18e8fbd6776c93b66d40c4a2c56b35925e25af3d6480f48b468447a79e';
    expect(PinHasher.hashPin('asha_001', '1234'), expected);
    expect(PinHasher.verify('ASHA_001', '1234', expected), isTrue);
    expect(PinHasher.verify('asha_001', '0000', expected), isFalse);
  });

  testWidgets(
      'Lock screen handles invalid PIN, offline re-unlock after first sign-in, and sign out',
      (tester) async {
    final fakeApi = FakeAshaApiClient();
    final appState = makeTestAppState(
      api: fakeApi,
      initialLanguage: AppLanguage.en,
    );

    await tester.pumpWidget(AshaVaaniApp(appState: appState));
    await tester.pumpAndSettle();

    // Wrong PIN surfaces inline error text
    await tester.enterText(find.byKey(const ValueKey('pin_field')), '9999');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Incorrect worker code or PIN.'), findsOneWidget);

    // Valid PIN online succeeds
    await tester.enterText(find.byKey(const ValueKey('pin_field')), '1234');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Namaste, Sunita Devi'), findsOneWidget);
    expect(appState.hasOfflineCredentials, isTrue);

    // Lock app, simulate offline backend, unlock offline with same PIN
    await appState.lockApp();
    await tester.pumpAndSettle();
    expect(find.text('Unlock'), findsOneWidget);
    expect(find.text('PIN lock · Offline ready'), findsOneWidget);

    fakeApi.loginError = const ApiException('NETWORK_ERROR');
    await tester.enterText(find.byKey(const ValueKey('pin_field')), '1234');
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();

    expect(find.text('Namaste, Sunita Devi'), findsOneWidget);
    expect(appState.isSignedInOffline, isTrue);
  });

  testWidgets(
      '4-tab V2 shell and Home dashboard render on 360x640 at 130% text scale without overflow',
      (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final todayIso = DateTime.now().toIso8601String().substring(0, 10);
    final fakeApi = FakeAshaApiClient()
      ..savedVisits = [
        VisitSummary(
          visitId: 'v-1',
          sessionId: 's-1',
          beneficiaryId: '1042',
          visitDate: todayIso,
          riskFlags: const ['low_birth_weight'],
          referralSuggested: true,
          status: 'saved',
          updatedAt: '${todayIso}T09:00:00Z',
        ),
      ];

    final appState = makeTestAppState(
      api: fakeApi,
      initialLanguage: AppLanguage.en,
      initialProfile: AshaProfile.defaults.first,
    );

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(360, 640),
          textScaler: TextScaler.linear(1.3),
        ),
        child: AshaVaaniApp(appState: appState),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // Home dashboard content: greeting, SyncChip, 3 StatTiles, due beneficiaries
    expect(find.text('Namaste, Sunita Devi'), findsOneWidget);
    expect(find.byType(SyncChip), findsOneWidget);
    expect(find.byType(StatTile), findsNWidgets(3));
    expect(find.text('Record visit'), findsOneWidget);

    // 1042 was visited today, so 2 beneficiaries remain due today (1043, 1057)
    final homeListFinder = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.text('Baby of Lakshmi (synthetic)'),
      150,
      scrollable: homeListFinder,
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Baby of Kavita (synthetic)'), findsOneWidget);
    expect(find.text('Baby of Lakshmi (synthetic)'), findsOneWidget);

    // Switch to Insights tab
    await tester.tap(find.text('Insights'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Confirmed visits'), findsOneWidget);

    // Switch to Settings tab and toggle High Contrast mode
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('High contrast mode'), findsOneWidget);

    await tester.tap(find.text('High contrast mode'));
    await tester.pumpAndSettle();
    expect(appState.highContrast, isTrue);

    // Sign out with ConfirmSheet
    final listFinder = find.byType(Scrollable).last;
    await tester.scrollUntilVisible(
      find.text('Sign out'),
      150,
      scrollable: listFinder,
    );
    await tester.ensureVisible(find.text('Sign out'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(find.byType(ConfirmSheet), findsOneWidget);

    await tester.tap(find.text('Sign out').last);
    await tester.pumpAndSettle();
    expect(find.text('Sign in'), findsOneWidget);
  });
}
