import 'package:asha_vaani/models/v2_models.dart';
import 'package:asha_vaani/services/due_engine.dart';
import 'package:asha_vaani/services/duplicate_detector.dart';
import 'package:asha_vaani/services/local_code_generator.dart';
import 'package:asha_vaani/services/local_db_schema.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  test('UuidV4 and LocalCodeGenerator produce unique collision-safe IDs', () {
    final ids = List.generate(25, (_) => UuidV4.generate()).toSet();
    expect(ids.length, 25);
    expect(
      RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')
          .hasMatch(ids.first),
      isTrue,
    );

    final next = LocalCodeGenerator.nextCode(
      existingCodes: const ['3001', '3002'],
      devicePrefix: 3,
    );
    expect(next, '3003');
  });

  test('DueEngine schedules HBNC newborn, ANC + EDD, and derives risk level', () {
    final dob = DateTime.utc(2026, 11, 1);
    expect(
      DueEngine.computeNextDueAt(beneficiaryType: 'newborn', dob: dob, today: dob),
      DateTime.utc(2026, 11, 4),
    );
    expect(
      DueEngine.computeNextDueAt(
        beneficiaryType: 'newborn',
        dob: dob,
        visitedAt: DateTime.utc(2026, 11, 4),
      ),
      DateTime.utc(2026, 11, 8),
    );
    expect(
      DueEngine.computeNextDueAt(
        beneficiaryType: 'newborn',
        dob: dob,
        visitedAt: DateTime.utc(2026, 12, 13),
      ),
      isNull,
    );

    final lmp = DateTime.utc(2026, 1, 1);
    expect(DueEngine.computeEdd(lmp), DateTime.utc(2026, 10, 8));
    expect(DueEngine.deriveRiskLevel(const []), 'none');
    expect(DueEngine.deriveRiskLevel(const ['mild_note']), 'watch');
    expect(DueEngine.deriveRiskLevel(const ['low_birth_weight']), 'high');
    expect(
      DueEngine.deriveRiskLevel(const [], referralSuggested: true),
      'high',
    );
  });

  test('DuplicateDetector normalizes honorifics/transliteration and avoids household false matches', () {
    expect(
      DuplicateDetector.normalizeName('Smt. Suneeta Devi'),
      DuplicateDetector.normalizeName('Sunita'),
    );

    final existing = [
      const BeneficiaryRecord(
        id: 'b-1',
        localCode: '1042',
        workerId: 'asha_001',
        areaId: 'area_1',
        fullName: 'Smt. Suneeta Devi',
        dob: '2000-05-10',
        phoneEnc: '+91 9876543210',
        createdAt: '2026-11-01T00:00:00Z',
        updatedAt: '2026-11-01T00:00:00Z',
      ),
      const BeneficiaryRecord(
        id: 'b-del',
        localCode: '1043',
        workerId: 'asha_001',
        areaId: 'area_1',
        fullName: 'Sunita',
        dob: '2000-05-10',
        status: 'closed',
        deletedAt: '2026-11-02T00:00:00Z',
        createdAt: '2026-11-01T00:00:00Z',
        updatedAt: '2026-11-01T00:00:00Z',
      ),
    ];

    final matches = DuplicateDetector.findCandidates(
      fullName: 'Sunita',
      workerId: 'asha_001',
      areaId: 'area_1',
      dob: '2000-07-01',
      phoneEnc: '9876543210',
      existing: existing,
    );
    expect(matches.length, 1);
    expect(matches.first.beneficiary.id, 'b-1');
    expect(matches.first.reasons, containsAll(['similar_name', 'same_phone']));

    // Baby sharing household phone with mother does not match mother
    final babyMatches = DuplicateDetector.findCandidates(
      fullName: 'Baby of Sunita',
      workerId: 'asha_001',
      areaId: 'area_1',
      dob: '2026-11-18',
      phoneEnc: '9876543210',
      existing: existing,
    );
    expect(babyMatches, isEmpty);
  });

  test('LocalDbSchema defines all 14 SPEC_V2 tables and 5 indexes at version 2', () {
    expect(kLocalDbVersion, 2);
    expect(LocalDbSchema.v2TableNames.length, 14);
    expect(LocalDbSchema.v2IndexNames.length, 5);
    final allTableSql = LocalDbSchema.createTableStatements.join('\n');
    for (final table in LocalDbSchema.v2TableNames) {
      expect(allTableSql, contains('CREATE TABLE IF NOT EXISTS $table'));
    }
    final allIndexSql = LocalDbSchema.createIndexStatements.join('\n');
    for (final index in LocalDbSchema.v2IndexNames) {
      expect(allIndexSql, contains(index));
    }
  });

  test('LocalDbService V2 enforces immutability, derived caches, amendments, LWW, soft delete, and retention', () async {
    final db = FakeLocalDbService();
    final ben = await db.upsertBeneficiaryV2(
      const BeneficiaryRecord(
        id: 'ben-uuid-1',
        localCode: '3001',
        workerId: 'asha_001',
        areaId: 'area_1',
        fullName: 'Baby of Asha',
        dob: '2026-11-15',
        beneficiaryType: 'newborn',
        createdAt: '2026-11-15T10:00:00Z',
        updatedAt: '2026-11-15T10:00:00Z',
      ),
      consent: const ConsentRecord(
        id: 'con-1',
        beneficiaryId: 'ben-uuid-1',
        givenAt: '2026-11-15T10:00:00Z',
      ),
    );
    expect(ben.consentId, 'con-1');
    expect(ben.nextDueAt, isNotNull);

    final visit = await db.confirmVisitV2(
      const VisitRecord(
        id: 'visit-uuid-1',
        clientId: 'client-1',
        beneficiaryId: 'ben-uuid-1',
        workerId: 'asha_001',
        visitedAt: '2026-11-18',
        payload: {'baby_weight_kg': 2.3, 'temperature_c': 37.8},
        riskFlags: ['low_birth_weight', 'elevated_temperature'],
        referralSuggested: true,
        updatedAt: '2026-11-18T11:00:00Z',
      ),
    );
    expect(visit.status, 'confirmed');
    expect(visit.nextDueAt, '2026-11-22');

    final updatedBen = await db.getBeneficiaryV2('ben-uuid-1');
    expect(updatedBen?.riskLevel, 'high');
    expect(updatedBen?.lastVisitAt, '2026-11-18');
    expect(updatedBen?.nextDueAt, '2026-11-22');

    final meas = await db.getVisitMeasurements('ben-uuid-1');
    expect(meas.length, 2);

    await expectLater(
      () => db.confirmVisitV2(visit),
      throwsA(isA<VisitImmutableException>()),
    );

    final (amended, amendment) = await db.amendVisitV2(
      visitId: 'visit-uuid-1',
      changedBy: 'asha_001',
      changes: {'baby_weight_kg': 2.8, 'temperature_c': 36.7},
      reason: 'Re-measured after warming baby',
      riskFlags: const [],
      referralSuggested: false,
    );
    expect(amended.status, 'amended');
    expect((amendment.changes['baby_weight_kg'] as Map)['before'], 2.3);
    expect((amendment.changes['baby_weight_kg'] as Map)['after'], 2.8);
    expect((await db.getBeneficiaryV2('ben-uuid-1'))?.riskLevel, 'none');

    // LWW skips stale updates
    final kept = await db.upsertBeneficiaryV2(
      const BeneficiaryRecord(
        id: 'ben-uuid-1',
        localCode: '3001',
        workerId: 'asha_001',
        fullName: 'Stale Name',
        createdAt: '2026-11-15T10:00:00Z',
        updatedAt: '2026-11-14T10:00:00Z',
        version: 1,
      ),
    );
    expect(kept.fullName, 'Baby of Asha');

    // Soft delete hides from active query
    await db.softDeleteBeneficiaryV2('ben-uuid-1', actorId: 'asha_001');
    expect(await db.getBeneficiariesV2('asha_001'), isEmpty);
    expect(
      (await db.getBeneficiariesV2('asha_001', includeDeleted: true)).length,
      1,
    );

    // Retention purges uploaded+confirmed audio asset
    final deletedPaths = <String>[];
    await db.saveAudioAsset(
      const AudioAssetRecord(
        id: 'aud-1',
        visitId: 'visit-uuid-1',
        path: '/tmp/visit1.wav',
        state: 'uploaded',
        createdAt: '2026-11-18T11:00:00Z',
      ),
    );
    final purged = await db.purgeExpiredAudioAssets(
      deleteFile: (p) async => deletedPaths.add(p),
    );
    expect(purged, ['aud-1']);
    expect(deletedPaths, ['/tmp/visit1.wav']);
  });
}
