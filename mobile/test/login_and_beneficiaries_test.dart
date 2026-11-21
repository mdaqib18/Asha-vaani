import 'package:asha_vaani/l10n/app_strings.dart';
import 'package:asha_vaani/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  testWidgets(
      'PIN sign-in opens V2 Home, navigates to Beneficiaries, switches language, and searches',
      (tester) async {
    final fakeApi = FakeAshaApiClient();
    final appState = makeTestAppState(
      api: fakeApi,
      initialLanguage: AppLanguage.en,
    );

    await tester.pumpWidget(AshaVaaniApp(appState: appState));
    await tester.pumpAndSettle();

    expect(find.text('Worker code'), findsOneWidget);
    expect(find.text('PIN lock active'), findsOneWidget);

    // Switch language to Hindi on lock screen
    await tester.tap(find.byKey(const ValueKey('lang_hi')));
    await tester.pumpAndSettle();
    expect(find.text('कार्यकर्ता कोड'), findsOneWidget);

    // Enter valid demo PIN 1234 and sign in -> enters V2 Home dashboard
    await tester.enterText(find.byKey(const ValueKey('pin_field')), '1234');
    await tester.tap(find.text('साइन इन करें'));
    await tester.pumpAndSettle();

    expect(find.text('नमस्ते, Sunita Devi'), findsOneWidget);

    // Open Beneficiaries tab
    await tester.tap(find.text('लाभार्थी'));
    await tester.pumpAndSettle();

    expect(find.text('1042'), findsOneWidget);
    expect(find.text('Baby of Sunita (synthetic)'), findsOneWidget);
    expect(find.text('Baby of Kavita (synthetic)'), findsOneWidget);

    // Switch language to Kannada and verify tab label updates
    await tester.tap(find.byKey(const ValueKey('lang_kn')));
    await tester.pumpAndSettle();
    expect(find.text('ಫಲಾನುಭವಿಗಳು'), findsWidgets);

    // Filter beneficiary list by ID "1043"
    await tester.enterText(find.byType(TextField), '1043');
    await tester.pumpAndSettle();
    expect(find.text('Baby of Kavita (synthetic)'), findsOneWidget);
    expect(find.text('Baby of Sunita (synthetic)'), findsNothing);
  });
}
