import 'package:asha_vaani/l10n/app_strings.dart';
import 'package:asha_vaani/main.dart';
import 'package:asha_vaani/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  testWidgets('login stub selects worker, switches languages, and searches beneficiaries',
      (tester) async {
    final fakeApi = FakeAshaApiClient();
    final appState = AppState(
      apiClient: fakeApi,
      recorder: FakeAudioCaptureService(),
      initialLanguage: AppLanguage.en,
    );

    await tester.pumpWidget(AshaVaaniApp(appState: appState));
    await tester.pumpAndSettle();

    expect(find.text('Select ASHA Worker'), findsOneWidget);
    expect(find.text('Sunita Devi'), findsOneWidget);

    // Switch language to Hindi on login screen
    await tester.tap(find.byKey(const ValueKey('lang_hi')));
    await tester.pumpAndSettle();
    expect(find.text('आशा कार्यकर्ता चुनें'), findsOneWidget);

    // Select Sunita Devi -> enters HomeScreen with BeneficiaryListScreen
    await tester.tap(find.text('Sunita Devi'));
    await tester.pumpAndSettle();

    expect(find.text('1042'), findsOneWidget);
    expect(find.text('Baby of Sunita (synthetic)'), findsOneWidget);
    expect(find.text('Baby of Kavita (synthetic)'), findsOneWidget);

    // Switch language to Kannada and verify tab label updates
    await tester.tap(find.byKey(const ValueKey('lang_kn')));
    await tester.pumpAndSettle();
    expect(find.text('ಫಲಾನುಭವಿಗಳು'), findsOneWidget);

    // Filter beneficiary list by ID "1043"
    await tester.enterText(find.byType(TextField), '1043');
    await tester.pumpAndSettle();
    expect(find.text('Baby of Kavita (synthetic)'), findsOneWidget);
    expect(find.text('Baby of Sunita (synthetic)'), findsNothing);
  });
}
