import 'package:asha_vaani/l10n/app_strings.dart';
import 'package:asha_vaani/models/beneficiary.dart';
import 'package:asha_vaani/models/newborn_visit.dart';
import 'package:asha_vaani/screens/add_beneficiary_screen.dart';
import 'package:asha_vaani/screens/beneficiary_list_screen.dart';
import 'package:asha_vaani/screens/beneficiary_profile_screen.dart';
import 'package:asha_vaani/screens/visit_purpose_picker_screen.dart';
import 'package:asha_vaani/services/api_client.dart';
import 'package:asha_vaani/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  testWidgets(
    'BeneficiaryListScreen filters by category and risk and opens BeneficiaryProfileScreen',
    (tester) async {
      final fakeApi = FakeAshaApiClient()
        ..beneficiaries = const [
          Beneficiary(
            id: '1042',
            label: 'Baby of Sunita (synthetic)',
            beneficiaryType: 'newborn',
            riskLevel: 'high',
            phoneMasked: '••••••3210',
            phoneLocal: '9876543210',
          ),
          Beneficiary(
            id: '1050',
            label: 'Anitha Devi',
            beneficiaryType: 'pregnant_woman',
            sex: 'female',
            eddDate: '2027-02-15',
            riskLevel: 'none',
            phoneMasked: '••••••7788',
            phoneLocal: '9876507788',
          ),
        ]
        ..profileVisitsById['1042'] = const BeneficiaryProfileVisits(
          beneficiaryId: '1042',
          measurements: [
            MeasurementPoint(
              key: 'baby_weight_kg',
              valueNum: 2.3,
              unit: 'kg',
              measuredAt: '2026-11-18',
            ),
            MeasurementPoint(
              key: 'baby_weight_kg',
              valueNum: 2.6,
              unit: 'kg',
              measuredAt: '2026-11-21',
            ),
          ],
          visits: [
            VisitSummary(
              visitId: 'v1',
              sessionId: 's1',
              beneficiaryId: '1042',
              riskFlags: ['low_birth_weight'],
              referralSuggested: true,
              status: 'saved',
              updatedAt: '2026-11-21T09:00:00Z',
            ),
          ],
        );

      final fakeDb = FakeLocalDbService();
      final appState = makeTestAppState(
        api: fakeApi,
        localDb: fakeDb,
        initialLanguage: AppLanguage.en,
        initialProfile: AshaProfile.defaults.first,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme(),
          home: Scaffold(
            body: BeneficiaryListScreen(
              appState: appState,
              onVisitSaved: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Baby of Sunita (synthetic)'), findsOneWidget);
      expect(find.text('Anitha Devi'), findsOneWidget);

      await tester.tap(find.text('Pregnant women'));
      await tester.pumpAndSettle();
      expect(find.text('Anitha Devi'), findsOneWidget);
      expect(find.text('Baby of Sunita (synthetic)'), findsNothing);

      await tester.tap(find.text('All'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Baby of Sunita (synthetic)'));
      await tester.pumpAndSettle();

      expect(find.byType(BeneficiaryProfileScreen), findsOneWidget);
      expect(find.textContaining('••••••3210'), findsOneWidget);
      expect(find.text('Health trends'), findsOneWidget);

      // Tap to reveal writes audit log
      await tester.tap(find.text('Tap to reveal'));
      await tester.pumpAndSettle();
      expect(find.textContaining('9876543210'), findsOneWidget);
      expect(
        fakeDb.auditLogV2.any((a) => a.action == 'pii_revealed'),
        isTrue,
      );
    },
  );

  testWidgets(
    'AddBeneficiaryScreen enforces consent, screens duplicates, saves offline, and opens ANC purpose picker on 360x640 @ 130%',
    (tester) async {
      final fakeApi = FakeAshaApiClient()
        ..createBeneficiaryError = const ApiException('NETWORK_ERROR')
        ..fakeDuplicateMatches.add(
          const DuplicateMatchItem(
            beneficiaryId: 'existing-1',
            localCode: '1090',
            fullName: 'Smt. Suneeta Devi',
            dob: '2000-05-10',
            score: 0.92,
            reasons: ['similar_name'],
          ),
        );
      final fakeDb = FakeLocalDbService();
      final appState = makeTestAppState(
        api: fakeApi,
        localDb: fakeDb,
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
          home: AddBeneficiaryScreen(
            appState: appState,
            existingBeneficiaries: fakeApi.beneficiaries,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Speak-to-add populates form fields when tapped twice (start & stop)
      await tester.tap(find.byKey(const ValueKey('speak_to_add_mic')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Listening...'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('speak_to_add_mic')));
      await tester.pumpAndSettle();

      final scrollable = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('add_ben_name')),
        150,
        scrollable: scrollable,
      );
      expect(find.text('Sunita'), findsWidgets);

      // Scroll to save button without consent -> blocked with consent error
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('save_beneficiary_button')),
        150,
        scrollable: scrollable,
      );
      await tester.tap(find.byKey(const ValueKey('save_beneficiary_button')));
      await tester.pumpAndSettle();
      expect(
        find.text('Consent must be confirmed before saving.'),
        findsOneWidget,
      );

      // Check consent and submit -> duplicate match card appears
      final consentBox = find.byKey(const ValueKey('add_ben_consent_checkbox'));
      await tester.ensureVisible(consentBox);
      await tester.pumpAndSettle();
      await tester.tap(consentBox);
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(const ValueKey('save_beneficiary_button')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('save_beneficiary_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('duplicate_match_card')), findsOneWidget);
      expect(find.text('Possible match found'), findsOneWidget);

      // Confirm saving as new person despite duplicate warning -> saves offline V2 record + sync queue
      await tester.ensureVisible(find.text('Save as new person'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save as new person'));
      await tester.pumpAndSettle();

      expect(find.text('Beneficiary saved'), findsWidgets);
      expect(find.text('Record first visit now'), findsOneWidget);
      expect(fakeDb.beneficiariesV2.length, 1);
      expect(fakeDb.consentsV2.length, 1);
      expect(fakeDb.syncQueueV2.length, 1);

      // Record first visit now -> opens VisitPurposePickerScreen with ANC suggested
      await tester.tap(find.text('Record first visit now'));
      await tester.pumpAndSettle();
      expect(find.byType(VisitPurposePickerScreen), findsOneWidget);
      expect(find.text('Antenatal check (ANC)'), findsOneWidget);
    },
  );
}
