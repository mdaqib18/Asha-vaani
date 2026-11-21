import 'dart:typed_data';

import 'package:asha_vaani/l10n/app_strings.dart';
import 'package:asha_vaani/models/beneficiary.dart';
import 'package:asha_vaani/models/newborn_visit.dart';
import 'package:asha_vaani/screens/beneficiary_list_screen.dart';
import 'package:asha_vaani/screens/record_visit_screen.dart';
import 'package:asha_vaani/screens/saved_visits_screen.dart';
import 'package:asha_vaani/services/api_client.dart';
import 'package:asha_vaani/services/sync_service.dart';
import 'package:asha_vaani/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  testWidgets('offline recording saves locally and auto-syncs on reconnect',
      (tester) async {
    final fakeApi = FakeAshaApiClient()
      ..uploadError = const ApiException('NETWORK_ERROR')
      ..savedVisitsError = const ApiException('NETWORK_ERROR');
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

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme(),
        home: RecordVisitScreen(
          appState: appState,
          beneficiary: const Beneficiary(
            id: '1042',
            label: 'Baby of Sunita (synthetic)',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Record > 500ms while offline -> Saved offline card shown
    final mic = find.byKey(const ValueKey('push_to_talk_button'));
    final gesture = await tester.startGesture(tester.getCenter(mic));
    await tester.pump(const Duration(milliseconds: 650));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.text('Saved offline'), findsOneWidget);
    expect(appState.syncService.pendingCount, 1);

    // Mount SavedVisitsScreen while offline -> shows Pending badge
    final refreshSignal = ValueNotifier<int>(0);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme(),
        home: Scaffold(
          body: SavedVisitsScreen(
            appState: appState,
            refreshSignal: refreshSignal,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Pending'), findsOneWidget);
    expect(find.text('1 recording(s) waiting to sync'), findsOneWidget);

    // Network returns -> connectivity triggers automatic sync
    fakeApi.savedVisitsError = null;
    fakeConn.emitOnline(true);
    await tester.pumpAndSettle();

    expect(fakeApi.syncCalls.length, 1);
    expect(appState.syncService.pendingCount, 0);
    expect(find.text('Ready to review'), findsOneWidget);
    expect(find.text('Pending'), findsNothing);
    refreshSignal.dispose();
  });

  testWidgets('BeneficiaryListScreen falls back to cached list when offline',
      (tester) async {
    final fakeApi = FakeAshaApiClient()
      ..beneficiariesError = const ApiException('NETWORK_ERROR');
    final fakeDb = FakeLocalDbService();
    await fakeDb.cacheBeneficiaries(
      'asha_001',
      const [Beneficiary(id: '1042', label: 'Baby of Sunita (synthetic)')],
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
        home: Scaffold(
          body: BeneficiaryListScreen(
            appState: appState,
            onVisitSaved: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Offline — showing saved list'), findsOneWidget);
    expect(find.text('Baby of Sunita (synthetic)'), findsOneWidget);
  });

  test('SyncService handles mixed batch results and cleans valid items', () async {
    final fakeApi = FakeAshaApiClient();
    final fakeDb = FakeLocalDbService();
    final fakeConn = FakeConnectivityMonitor(initialOnline: false);
    final deleted = <String>[];

    final sync = SyncService(
      localDb: fakeDb,
      apiProvider: () => fakeApi,
      connectivity: fakeConn,
      persistAudioFile: (tmp, id) async => '/offline/$id.wav',
      readAudioBytes: (_) async => Uint8List.fromList([1, 2, 3, 4]),
      deleteAudioFile: (p) async => deleted.add(p),
    );

    final q1 = await sync.saveRecordingOffline(
      tempFilePath: '/tmp/a.wav',
      ashaId: 'asha_001',
      beneficiary: const Beneficiary(id: '1042', label: 'Baby of Sunita'),
      language: 'hi',
    );
    final q2 = await sync.saveRecordingOffline(
      tempFilePath: '/tmp/b.wav',
      ashaId: 'asha_001',
      beneficiary: const Beneficiary(id: '1043', label: 'Baby of Kavita'),
      language: 'hi',
    );
    expect(sync.pendingCount, 2);

    fakeApi.onSyncBatch = (items) => [
          SyncItemResult(
            clientId: q1.clientId,
            ok: true,
            result: const VisitTurnResponse(
              sessionId: 'sess-good',
              transcript: 'weight 2.5 kg',
              record: NewbornVisitRecord(babyWeightKg: ExtractedField(value: 2.5)),
              status: 'ready_to_confirm',
            ),
          ),
          SyncItemResult(
            clientId: q2.clientId,
            ok: false,
            errorCode: 'INVALID_AUDIO',
            errorMessage: 'Corrupt audio',
          ),
        ];

    final synced = await sync.syncPending();
    expect(synced, 1);
    expect(sync.pendingCount, 0);
    expect(deleted, [q1.audioPath]);
    final drafts = await fakeDb.getDrafts(ashaId: 'asha_001');
    expect(drafts.length, 1);
    expect(drafts.first.sessionId, 'sess-good');
    expect(fakeDb.queue[q2.clientId]?.status, 'error_permanent');
  });
}
