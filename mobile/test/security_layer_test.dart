import 'dart:io';

import 'package:asha_vaani/l10n/app_strings.dart';
import 'package:asha_vaani/models/beneficiary.dart';
import 'package:asha_vaani/models/v2_models.dart';
import 'package:asha_vaani/screens/home_dashboard_screen.dart';
import 'package:asha_vaani/screens/login_screen.dart';
import 'package:asha_vaani/screens/privacy_and_data_screen.dart';
import 'package:asha_vaani/screens/record_visit_screen.dart';
import 'package:asha_vaani/screens/settings_screen.dart';
import 'package:asha_vaani/services/biometric_auth_service.dart';
import 'package:asha_vaani/services/prefs_service.dart';
import 'package:asha_vaani/services/screen_security_service.dart';
import 'package:asha_vaani/services/secure_storage_service.dart';
import 'package:asha_vaani/state/app_state.dart';
import 'package:asha_vaani/theme/app_theme.dart';
import 'package:asha_vaani/widgets/auto_lock_wrapper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

void main() {
  test(
    'SecureStorage migrates legacy secrets, lockApp clears session and closes DB, signOut wipes credentials',
    () async {
      SharedPreferences.setMockInitialValues({
        'asha_id': 'asha_001',
        'session_token': 'legacy-token',
        'pin_digest': 'legacy-digest',
        'last_worker_id': 'asha_001',
        'last_worker_name': 'Lakshmi',
        'last_worker_area': 'Rampur',
      });
      final prefs = PrefsService(await SharedPreferences.getInstance());
      final secure = InMemorySecureStorageService();
      final db = FakeLocalDbService();
      final appState = AppState(
        prefs: prefs,
        apiClient: FakeAshaApiClient(),
        recorder: FakeAudioCaptureService(),
        audioPlayer: FakeAudioPlaybackService(),
        connectivity: FakeConnectivityMonitor(),
        localDb: db,
        secureStorage: secure,
        biometricAuth: FakeBiometricAuthService(available: true),
        screenSecurity: FakeScreenSecurityService(),
      );

      final k1 = await secure.getOrCreateDbPassphrase();
      final k2 = await secure.getOrCreateDbPassphrase();
      expect(k1, isNotEmpty);
      expect(k2, equals(k1));

      await appState.initializeSecurity();
      expect(prefs.pinDigest, isNull);
      expect(prefs.sessionToken, isNull);
      expect(await secure.readPinDigest(), equals('legacy-digest'));
      expect(appState.biometricAvailable, isTrue);

      await appState.signInWithPin(workerCode: 'asha_001', pin: '1234');
      expect(appState.isLocked, isFalse);
      expect(appState.sessionToken, isNotNull);

      await appState.lockApp();
      expect(appState.isLocked, isTrue);
      expect(appState.sessionToken, isNull);
      expect(appState.hasOfflineCredentials, isTrue);
      expect(db.closeCalls, 1);

      await appState.signOut();
      expect(appState.selectedProfile, isNull);
      expect(appState.hasOfflineCredentials, isFalse);
      expect(await secure.readSessionToken(), isNull);
      expect(await secure.readPinDigest(), isNull);
      expect(db.closeCalls, 2);
    },
  );

  testWidgets(
    'AutoLockWrapper relocks after background elapsed time and foreground inactivity',
    (tester) async {
      final db = FakeLocalDbService();
      final appState = makeTestAppState(
        api: FakeAshaApiClient(),
        localDb: db,
        initialProfile: AshaProfile.defaults.first,
        initialLocked: false,
      );
      await appState.setAutoLockSeconds(60);

      var clock = DateTime.utc(2026, 11, 22, 10, 0, 0);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme(),
          home: AutoLockWrapper(
            appState: appState,
            now: () => clock,
            child: const Scaffold(body: Text('Active session')),
          ),
        ),
      );

      // Background >= 60s triggers relock on resume
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      clock = clock.add(const Duration(seconds: 65));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(appState.isLocked, isTrue);

      // Unlock & verify foreground inactivity timer locks after 60s
      await appState.signInWithPin(workerCode: 'asha_001', pin: '1234');
      expect(appState.isLocked, isFalse);
      await tester.pump(const Duration(seconds: 61));
      expect(appState.isLocked, isTrue);
    },
  );

  testWidgets(
    'LoginScreen unlocks via BiometricAuthService when locked and hardware available',
    (tester) async {
      final api = FakeAshaApiClient();
      final db = FakeLocalDbService();
      final bio = FakeBiometricAuthService(available: true, shouldSucceed: true);
      final appState = makeTestAppState(
        api: api,
        localDb: db,
        biometricAuth: bio,
      );
      await appState.initializeSecurity();
      await appState.signInWithPin(workerCode: 'asha_001', pin: '1234');
      await appState.lockApp();

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme(),
          home: LoginScreen(appState: appState),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Encrypted on this device'), findsOneWidget);
      expect(find.text('Unlock with biometric'), findsOneWidget);

      await tester.tap(find.text('Unlock with biometric'));
      await tester.pumpAndSettle();

      expect(bio.authCalls, 1);
      expect(appState.isLocked, isFalse);
      expect(
        db.auditLogV2.any((e) => e.action == 'biometric_unlock'),
        isTrue,
      );
    },
  );

  testWidgets(
    'SettingsScreen dev screenshot toggle controls ScreenSecurityService and stays hidden when disallowed',
    (tester) async {
      final screenSec = FakeScreenSecurityService();
      final devState = makeTestAppState(
        api: FakeAshaApiClient(),
        screenSecurity: screenSec,
        initialProfile: AshaProfile.defaults.first,
        allowDevSecurityToggle: true,
      );
      final refresh = ValueNotifier<int>(0);
      addTearDown(refresh.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme(),
          home: Scaffold(
            body: SettingsScreen(appState: devState, refreshSignal: refresh),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final toggle = find.byKey(const ValueKey('dev_screenshot_protection_toggle'));
      expect(toggle, findsOneWidget);

      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(screenSec.calls, contains(false));
      expect(devState.isScreenProtected, isFalse);

      // Prod/non-dev build flag hides the dev toggle completely
      final prodState = makeTestAppState(
        api: FakeAshaApiClient(),
        screenSecurity: FakeScreenSecurityService(),
        initialProfile: AshaProfile.defaults.first,
        allowDevSecurityToggle: false,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme(),
          home: Scaffold(
            body: SettingsScreen(appState: prodState, refreshSignal: refresh),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('dev_screenshot_protection_toggle')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'RecordVisitScreen blocks microphone until visit consent is recorded to ConsentRecord',
    (tester) async {
      final db = FakeLocalDbService();
      final appState = makeTestAppState(
        api: FakeAshaApiClient(),
        localDb: db,
        initialProfile: AshaProfile.defaults.first,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme(),
          home: RecordVisitScreen(
            appState: appState,
            beneficiary: const Beneficiary(
              id: '1042',
              uuid: 'ben-unconsented',
              label: 'Baby of Meera',
              consentRecorded: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('push_to_talk_button')), findsNothing);
      final consentCheckbox = find.byKey(const ValueKey('visit_consent_checkbox'));
      expect(consentCheckbox, findsOneWidget);

      await tester.tap(consentCheckbox);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('push_to_talk_button')), findsOneWidget);
      final savedConsents = await db.getConsentsForBeneficiary('ben-unconsented');
      expect(savedConsents, hasLength(1));
      expect(savedConsents.first.kind, 'visit_recording');
      expect(
        db.auditLogV2.any((e) => e.action == 'visit_consent_recorded'),
        isTrue,
      );
    },
  );

  testWidgets(
    'PrivacyAndDataScreen shows real security status, purges expired audio, and renders without overflow on 360x640 at 130%',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final tmpFile = File('${Directory.systemTemp.path}/expired_demo_sec.wav')
        ..writeAsBytesSync([1, 2, 3]);
      addTearDown(() {
        if (tmpFile.existsSync()) tmpFile.deleteSync();
      });

      final db = FakeLocalDbService(encrypted: true);
      await db.saveAudioAsset(
        AudioAssetRecord(
          id: 'aud_exp_1',
          visitId: null,
          path: tmpFile.path,
          state: 'local',
          deleteAfter: DateTime.now()
              .toUtc()
              .subtract(const Duration(days: 1))
              .toIso8601String(),
          createdAt: DateTime.now()
              .toUtc()
              .subtract(const Duration(days: 8))
              .toIso8601String(),
        ),
      );

      final appState = makeTestAppState(
        api: FakeAshaApiClient(),
        localDb: db,
        initialProfile: AshaProfile.defaults.first,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(1.3),
            ),
            child: child!,
          ),
          home: PrivacyAndDataScreen(appState: appState),
        ),
      );
      await tester.pumpAndSettle();

      // Honest transport check for default http:// baseUrl
      expect(find.textContaining('HTTP'), findsOneWidget);
      expect(find.text('HTTPS encrypted'), findsNothing);

      await tester.scrollUntilVisible(
        find.text('Run audio retention cleanup'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.text('Run audio retention cleanup'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Run audio retention cleanup'));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('1 expired audio recording(s) deleted.'),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('1 expired audio recording(s) deleted.'), findsOneWidget);
      expect(tmpFile.existsSync(), isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'HomeDashboardScreen SyncChip reports Encrypted only on https:// transport',
    (tester) async {
      final api = FakeAshaApiClient();
      final db = FakeLocalDbService(encrypted: true);
      final appState = makeTestAppState(
        api: api,
        localDb: db,
        initialLanguage: AppLanguage.en,
        initialProfile: AshaProfile.defaults.first,
      );
      final refresh = ValueNotifier<int>(0);
      addTearDown(refresh.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme(),
          home: Scaffold(
            body: HomeDashboardScreen(
              appState: appState,
              refreshSignal: refresh,
              onSelectTab: (_) {},
              onVisitSaved: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Synced'), findsOneWidget);
      expect(find.text('Encrypted · Synced'), findsNothing);

      await appState.updateBaseUrl('https://api.ashavaani.in', customClient: api);
      await tester.pumpAndSettle();
      expect(find.text('Encrypted · Synced'), findsOneWidget);
    },
  );
}
