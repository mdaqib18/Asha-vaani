import '../l10n/app_strings.dart';
import '../models/beneficiary.dart';
import '../models/v2_models.dart';
import '../models/visit_type.dart';
import 'due_engine.dart';
import 'local_db_service.dart';

enum StatsPeriod {
  today,
  sevenDays,
  thirtyDays;

  int get days => switch (this) {
        StatsPeriod.today => 1,
        StatsPeriod.sevenDays => 7,
        StatsPeriod.thirtyDays => 30,
      };

  String get apiValue => switch (this) {
        StatsPeriod.today => 'today',
        StatsPeriod.sevenDays => '7d',
        StatsPeriod.thirtyDays => '30d',
      };
}

class DailyVisitBucket {
  const DailyVisitBucket({
    required this.date,
    required this.count,
    required this.highRiskCount,
  });

  final DateTime date;
  final int count;
  final int highRiskCount;
}

class CategoryCount {
  const CategoryCount({
    required this.key,
    required this.label,
    required this.count,
    required this.share,
  });

  final String key;
  final String label;
  final int count;
  final double share;
}

class DueBeneficiaryItem {
  const DueBeneficiaryItem({
    required this.beneficiary,
    required this.daysOverdue,
    required this.nextDueAt,
  });

  final Beneficiary beneficiary;
  final int daysOverdue;
  final DateTime nextDueAt;
}

class LocalInsightsReport {
  const LocalInsightsReport({
    required this.period,
    required this.visitsDone,
    required this.dueToday,
    required this.overdue,
    required this.activeBeneficiaries,
    required this.coverage,
    required this.highRiskOpen,
    required this.referralsSuggested,
    required this.avgRecordSeconds,
    required this.voiceShare,
    required this.followupRate,
    required this.pendingSyncCount,
    required this.hasDemoData,
    required this.dailySeries,
    required this.byPurpose,
    required this.riskBreakdown,
    required this.dueList,
    required this.estimatedMinutesSavedPerVisit,
    required this.estimatedMinutesSavedTotal,
  });

  final StatsPeriod period;
  final int visitsDone;
  final int dueToday;
  final int overdue;
  final int activeBeneficiaries;
  final double coverage;
  final int highRiskOpen;
  final int referralsSuggested;
  final double? avgRecordSeconds;
  final double? voiceShare;
  final double? followupRate;
  final int pendingSyncCount;
  final bool hasDemoData;
  final List<DailyVisitBucket> dailySeries;
  final List<CategoryCount> byPurpose;
  final List<CategoryCount> riskBreakdown;
  final List<DueBeneficiaryItem> dueList;
  final double? estimatedMinutesSavedPerVisit;
  final double? estimatedMinutesSavedTotal;
}

class _NormalizedVisit {
  const _NormalizedVisit({
    required this.id,
    required this.beneficiaryId,
    required this.visitTypeCode,
    required this.visitedDay,
    required this.riskFlags,
    required this.referralSuggested,
    required this.inputMethod,
    required this.durationSeconds,
    required this.hasFollowup,
    required this.isDemo,
  });

  final String id;
  final String? beneficiaryId;
  final String visitTypeCode;
  final DateTime? visitedDay;
  final List<String> riskFlags;
  final bool referralSuggested;
  final String inputMethod;
  final double? durationSeconds;
  final bool hasFollowup;
  final bool isDemo;
}

/// Offline-first statistical engine computed strictly from local SQLite records (SPEC_V2 §6).
class LocalStatsEngine {
  LocalStatsEngine._();

  static const String demoPrefix = 'demo_seed_';

  static const Map<String, int> _riskRank = {
    'high': 0,
    'watch': 1,
    'medium': 1,
    'low': 2,
    'none': 3,
  };

  static DateTime _utcDay(DateTime dt) => DateTime.utc(dt.year, dt.month, dt.day);

  static DateTime? _parseUtcDay(String? raw) {
    final parsed = DueEngine.parseIsoDate(raw);
    return parsed == null ? null : _utcDay(parsed);
  }

  static double? _measureDurationSeconds(String? startedAt, String? confirmedAt) {
    if (startedAt == null || confirmedAt == null) return null;
    final start = DateTime.tryParse(startedAt);
    final end = DateTime.tryParse(confirmedAt);
    if (start == null || end == null) return null;
    final secs = end.difference(start).inMilliseconds / 1000.0;
    if (secs < 0 || secs > 3600) return null;
    return secs;
  }

  static String _humanizeKey(String raw) {
    final parts = raw
        .trim()
        .replaceAll('-', '_')
        .split('_')
        .where((p) => p.isNotEmpty)
        .map((p) => '${p[0].toUpperCase()}${p.substring(1)}');
    return parts.isEmpty ? raw : parts.join(' ');
  }

  static bool _isDemoBeneficiary(BeneficiaryRecord b) =>
      b.id.startsWith(demoPrefix) || b.localCode.startsWith('D-');

  static bool _isDemoVisit(VisitRecord v) =>
      v.id.startsWith(demoPrefix) || (v.clientId?.startsWith(demoPrefix) ?? false);

  static Future<LocalInsightsReport> compute({
    required LocalDbService localDb,
    required String workerId,
    required StatsPeriod period,
    required AppStrings strings,
    required AppLanguage language,
    double? paperBaselineMinutes,
    DateTime? today,
  }) async {
    final now = today ?? DateTime.now().toUtc();
    final refToday = _utcDay(now);
    final startDate = refToday.subtract(Duration(days: period.days - 1));
    final coverageStart = refToday.subtract(const Duration(days: 29));

    final beneficiaries = (await localDb.getBeneficiariesV2(workerId))
        .where((b) => b.deletedAt == null && b.status == 'active')
        .toList();
    final v2Visits = await localDb.getVisitsV2(workerId: workerId);
    final followupVisitIds = await localDb.getFollowupVisitIdsV2(workerId);
    final cachedVisits = await localDb.getCachedVisits(workerId);
    final pendingAudio = await localDb.getPendingQueue(ashaId: workerId);
    final syncQueueV2 = await localDb.getSyncQueueV2();

    final codeToId = <String, String>{
      for (final b in beneficiaries) b.localCode: b.id,
    };
    final activeIds = {for (final b in beneficiaries) b.id};

    var hasDemoData = beneficiaries.any(_isDemoBeneficiary);
    var dueToday = 0;
    var overdue = 0;
    var highRiskOpen = 0;
    final dueItems = <DueBeneficiaryItem>[];

    for (final b in beneficiaries) {
      if (b.riskLevel == 'high') {
        highRiskOpen++;
      }
      final dueDay = _parseUtcDay(b.nextDueAt);
      if (dueDay == null) continue;
      final daysOverdue = refToday.difference(dueDay).inDays;
      if (dueDay.isBefore(refToday)) {
        overdue++;
      } else if (dueDay == refToday) {
        dueToday++;
      }
      if (!dueDay.isAfter(refToday)) {
        dueItems.add(
          DueBeneficiaryItem(
            beneficiary: Beneficiary.fromV2Record(b),
            daysOverdue: daysOverdue < 0 ? 0 : daysOverdue,
            nextDueAt: dueDay,
          ),
        );
      }
    }

    dueItems.sort((a, b) {
      final overdueCmp = b.daysOverdue.compareTo(a.daysOverdue);
      if (overdueCmp != 0) return overdueCmp;
      final ra = _riskRank[a.beneficiary.riskLevel] ?? 3;
      final rb = _riskRank[b.beneficiary.riskLevel] ?? 3;
      if (ra != rb) return ra.compareTo(rb);
      final dueCmp = a.nextDueAt.compareTo(b.nextDueAt);
      if (dueCmp != 0) return dueCmp;
      return a.beneficiary.id.compareTo(b.beneficiary.id);
    });

    final normalizedVisits = <_NormalizedVisit>[];
    final seenIds = <String>{};

    for (final v in v2Visits) {
      seenIds.add(v.id);
      if (v.clientId != null && v.clientId!.isNotEmpty) {
        seenIds.add(v.clientId!);
      }
      final isDemo = _isDemoVisit(v);
      if (isDemo) hasDemoData = true;

      if (v.status != 'confirmed' && v.status != 'amended') continue;

      final vDay = _parseUtcDay(v.visitedAt) ??
          _parseUtcDay(v.confirmedAt) ??
          _parseUtcDay(v.updatedAt);
      final method = v.inputMethod.trim().toLowerCase();
      final duration = method == 'voice'
          ? _measureDurationSeconds(v.startedAt, v.confirmedAt)
          : null;
      final payloadFu = (v.payload['followup_count'] as num?)?.toInt() ?? 0;

      normalizedVisits.add(
        _NormalizedVisit(
          id: v.id,
          beneficiaryId: v.beneficiaryId != null
              ? (codeToId[v.beneficiaryId!] ?? v.beneficiaryId)
              : null,
          visitTypeCode: v.visitTypeCode.isEmpty
              ? 'newborn_home_visit'
              : v.visitTypeCode,
          visitedDay: vDay,
          riskFlags: v.riskFlags,
          referralSuggested: v.referralSuggested,
          inputMethod: method.isEmpty ? 'voice' : method,
          durationSeconds: duration,
          hasFollowup: followupVisitIds.contains(v.id) || payloadFu > 0,
          isDemo: isDemo,
        ),
      );
    }

    for (final s in cachedVisits) {
      final keyId = s.visitId ?? s.sessionId;
      if (seenIds.contains(keyId) || seenIds.contains(s.sessionId)) continue;
      if (s.status != 'saved' && s.status != 'confirmed' && s.status != 'amended') {
        continue;
      }
      seenIds.add(keyId);
      final isDemo = keyId.startsWith(demoPrefix) || s.sessionId.startsWith(demoPrefix);
      if (isDemo) hasDemoData = true;
      final vDay = _parseUtcDay(s.visitDate) ?? _parseUtcDay(s.updatedAt);
      normalizedVisits.add(
        _NormalizedVisit(
          id: keyId,
          beneficiaryId: s.beneficiaryId != null
              ? (codeToId[s.beneficiaryId!] ?? s.beneficiaryId)
              : null,
          visitTypeCode: 'newborn_home_visit',
          visitedDay: vDay,
          riskFlags: s.riskFlags,
          referralSuggested: s.referralSuggested,
          inputMethod: 'voice',
          durationSeconds: null,
          hasFollowup: false,
          isDemo: isDemo,
        ),
      );
    }

    bool inWindow(DateTime? d, DateTime start, DateTime end) =>
        d != null && !d.isBefore(start) && !d.isAfter(end);

    final periodVisits = normalizedVisits
        .where((v) => inWindow(v.visitedDay, startDate, refToday))
        .toList();

    final visitsDone = periodVisits.length;
    final referralsSuggested =
        periodVisits.where((v) => v.referralSuggested).length;

    final voiceDurations = periodVisits
        .map((v) => v.durationSeconds)
        .whereType<double>()
        .toList();
    final double? avgRecordSeconds = voiceDurations.isEmpty
        ? null
        : voiceDurations.reduce((a, b) => a + b) / voiceDurations.length;

    final double? voiceShare = visitsDone == 0
        ? null
        : periodVisits
                .where(
                  (v) => v.inputMethod == 'voice' || v.inputMethod == 'mixed',
                )
                .length /
            visitsDone;

    final double? followupRate = visitsDone == 0
        ? null
        : periodVisits.where((v) => v.hasFollowup).length / visitsDone;

    final visitedLast30Ids = normalizedVisits
        .where(
          (v) =>
              inWindow(v.visitedDay, coverageStart, refToday) &&
              v.beneficiaryId != null &&
              activeIds.contains(v.beneficiaryId),
        )
        .map((v) => v.beneficiaryId!)
        .toSet();
    final double coverage = beneficiaries.isEmpty
        ? 0.0
        : visitedLast30Ids.length / beneficiaries.length;

    // Daily timeseries across [startDate..refToday]
    final dayCounts = <String, ({int count, int highRisk})>{};
    final series = <DailyVisitBucket>[];
    var cursor = startDate;
    while (!cursor.isAfter(refToday)) {
      dayCounts[DueEngine.formatIsoDate(cursor)] = (count: 0, highRisk: 0);
      cursor = cursor.add(const Duration(days: 1));
    }
    for (final v in periodVisits) {
      final iso = DueEngine.formatIsoDate(v.visitedDay!);
      final prev = dayCounts[iso];
      if (prev == null) continue;
      final isFlagged = v.referralSuggested || v.riskFlags.isNotEmpty;
      dayCounts[iso] = (
        count: prev.count + 1,
        highRisk: prev.highRisk + (isFlagged ? 1 : 0),
      );
    }
    cursor = startDate;
    while (!cursor.isAfter(refToday)) {
      final iso = DueEngine.formatIsoDate(cursor);
      final bucket = dayCounts[iso]!;
      series.add(
        DailyVisitBucket(
          date: cursor,
          count: bucket.count,
          highRiskCount: bucket.highRisk,
        ),
      );
      cursor = cursor.add(const Duration(days: 1));
    }

    // By purpose breakdown
    final purposeCounts = <String, int>{};
    for (final v in periodVisits) {
      purposeCounts[v.visitTypeCode] =
          (purposeCounts[v.visitTypeCode] ?? 0) + 1;
    }
    final byPurpose = purposeCounts.entries.map((entry) {
      final visitType = BuiltInVisitTypes.findByCode(entry.key);
      final label = visitType?.localizedName(language) ?? _humanizeKey(entry.key);
      return CategoryCount(
        key: entry.key,
        label: label,
        count: entry.value,
        share: visitsDone == 0 ? 0.0 : entry.value / visitsDone,
      );
    }).toList()
      ..sort((a, b) {
        final cmp = b.count.compareTo(a.count);
        return cmp != 0 ? cmp : a.key.compareTo(b.key);
      });

    // Risk flag breakdown
    final flagCounts = <String, int>{};
    for (final v in periodVisits) {
      for (final flag in v.riskFlags.toSet()) {
        if (flag.trim().isEmpty) continue;
        flagCounts[flag] = (flagCounts[flag] ?? 0) + 1;
      }
    }
    final totalFlags = flagCounts.values.fold<int>(0, (sum, c) => sum + c);
    final riskBreakdown = flagCounts.entries.map((entry) {
      final localized = strings.riskFlagLabel(entry.key);
      final label = localized == entry.key ? _humanizeKey(entry.key) : localized;
      return CategoryCount(
        key: entry.key,
        label: label,
        count: entry.value,
        share: totalFlags == 0 ? 0.0 : entry.value / totalFlags,
      );
    }).toList()
      ..sort((a, b) {
        final cmp = b.count.compareTo(a.count);
        return cmp != 0 ? cmp : a.key.compareTo(b.key);
      });

    // SPEC_V2 §6.3 Honesty rule: "Time saved" shown ONLY with user paper baseline + measured voice time.
    double? estSavedPerVisit;
    double? estSavedTotal;
    if (paperBaselineMinutes != null &&
        paperBaselineMinutes > 0 &&
        avgRecordSeconds != null) {
      estSavedPerVisit = paperBaselineMinutes - (avgRecordSeconds / 60.0);
      estSavedTotal = estSavedPerVisit * voiceDurations.length;
    }

    final pendingIds = <String>{
      ...pendingAudio.map((p) => p.clientId),
      ...syncQueueV2.map((s) => s.id),
    };

    return LocalInsightsReport(
      period: period,
      visitsDone: visitsDone,
      dueToday: dueToday,
      overdue: overdue,
      activeBeneficiaries: beneficiaries.length,
      coverage: coverage,
      highRiskOpen: highRiskOpen,
      referralsSuggested: referralsSuggested,
      avgRecordSeconds: avgRecordSeconds,
      voiceShare: voiceShare,
      followupRate: followupRate,
      pendingSyncCount: pendingIds.length,
      hasDemoData: hasDemoData,
      dailySeries: series,
      byPurpose: byPurpose,
      riskBreakdown: riskBreakdown,
      dueList: dueItems,
      estimatedMinutesSavedPerVisit: estSavedPerVisit,
      estimatedMinutesSavedTotal: estSavedTotal,
    );
  }

  /// Idempotent local SQLite demo seed matching the backend seeder (SPEC_V2 §6.3).
  static Future<int> seedDemoData(
    LocalDbService localDb, {
    required String workerId,
    DateTime? today,
  }) async {
    final now = (today ?? DateTime.now().toUtc()).toUtc();
    final refToday = _utcDay(now);
    final createdIso = now.toIso8601String();

    final existingBens = await localDb.getBeneficiariesV2(workerId);
    final existingBenIds = {for (final b in existingBens) b.id};
    final existingVisits = await localDb.getVisitsV2(workerId: workerId);
    final existingVisitIds = {for (final v in existingVisits) v.id};

    final benSpecs = <({
      String id,
      String code,
      String name,
      String type,
      String sex,
      String dob,
      String area,
      String? lmp,
    })>[
      (
        id: '${demoPrefix}ben_1',
        code: 'D-101',
        name: 'Demo Baby Aarav',
        type: 'newborn',
        sex: 'male',
        dob: DueEngine.formatIsoDate(refToday.subtract(const Duration(days: 9))),
        area: 'Ward 2 Rampur',
        lmp: null,
      ),
      (
        id: '${demoPrefix}ben_2',
        code: 'D-102',
        name: 'Demo Kavita Devi',
        type: 'pregnant_woman',
        sex: 'female',
        dob: '1998-04-12',
        area: 'Ward 2 Rampur',
        lmp: DueEngine.formatIsoDate(refToday.subtract(const Duration(days: 190))),
      ),
      (
        id: '${demoPrefix}ben_3',
        code: 'D-103',
        name: 'Demo Rohan Kumar',
        type: 'child_u5',
        sex: 'male',
        dob: DueEngine.formatIsoDate(refToday.subtract(const Duration(days: 760))),
        area: 'Ward 3 Devpur',
        lmp: null,
      ),
      (
        id: '${demoPrefix}ben_4',
        code: 'D-104',
        name: 'Demo Meera Bai',
        type: 'adult',
        sex: 'female',
        dob: '1972-09-20',
        area: 'Ward 3 Devpur',
        lmp: null,
      ),
      (
        id: '${demoPrefix}ben_5',
        code: 'D-105',
        name: 'Demo Baby Ananya',
        type: 'newborn',
        sex: 'female',
        dob: DueEngine.formatIsoDate(refToday.subtract(const Duration(days: 21))),
        area: 'Ward 1 Kendra',
        lmp: null,
      ),
      (
        id: '${demoPrefix}ben_6',
        code: 'D-106',
        name: 'Demo Sita Verma',
        type: 'pregnant_woman',
        sex: 'female',
        dob: '2000-02-18',
        area: 'Ward 1 Kendra',
        lmp: DueEngine.formatIsoDate(refToday.subtract(const Duration(days: 145))),
      ),
    ];

    var createdCount = 0;
    for (final spec in benSpecs) {
      if (existingBenIds.contains(spec.id)) continue;
      final dobDt = DueEngine.parseIsoDate(spec.dob);
      final lmpDt = DueEngine.parseIsoDate(spec.lmp);
      final dueDt = DueEngine.computeNextDueAt(
        beneficiaryType: spec.type,
        dob: dobDt,
        lmpDate: lmpDt,
        today: refToday,
      );
      await localDb.upsertBeneficiaryV2(
        BeneficiaryRecord(
          id: spec.id,
          localCode: spec.code,
          workerId: workerId,
          areaId: spec.area,
          fullName: spec.name,
          sex: spec.sex,
          dob: spec.dob,
          beneficiaryType: spec.type,
          nextDueAt: dueDt != null ? DueEngine.formatIsoDate(dueDt) : null,
          createdAt: createdIso,
          updatedAt: createdIso,
          version: 1,
        ),
        pregnancy: spec.lmp != null
            ? PregnancyRecord(
                id: '${demoPrefix}preg_${spec.code}',
                beneficiaryId: spec.id,
                lmpDate: spec.lmp,
                eddDate: lmpDt != null
                    ? DueEngine.formatIsoDate(DueEngine.computeEdd(lmpDt))
                    : null,
                createdAt: createdIso,
                updatedAt: createdIso,
              )
            : null,
        consent: ConsentRecord(
          id: '${demoPrefix}consent_${spec.code}',
          beneficiaryId: spec.id,
          givenBy: 'self',
          method: 'verbal',
          givenAt: createdIso,
        ),
        actorId: workerId,
      );
      createdCount++;
    }

    final visitSpecs = <({
      int idx,
      String benId,
      String purpose,
      int daysAgo,
      String method,
      int durSecs,
      Map<String, dynamic> payload,
      List<String> flags,
      bool referral,
      bool hasFollowup,
    })>[
      (
        idx: 1,
        benId: '${demoPrefix}ben_1',
        purpose: 'newborn_home_visit',
        daysAgo: 0,
        method: 'voice',
        durSecs: 44,
        payload: {'weight_kg': 2.25, 'temperature_c': 36.2},
        flags: ['low_birth_weight', 'hypothermia'],
        referral: true,
        hasFollowup: true,
      ),
      (
        idx: 2,
        benId: '${demoPrefix}ben_4',
        purpose: 'ncd_screening',
        daysAgo: 0,
        method: 'mixed',
        durSecs: 38,
        payload: {'bp_systolic': 132, 'bp_diastolic': 84},
        flags: [],
        referral: false,
        hasFollowup: false,
      ),
      (
        idx: 3,
        benId: '${demoPrefix}ben_2',
        purpose: 'anc_visit',
        daysAgo: 1,
        method: 'voice',
        durSecs: 52,
        payload: {'bp_systolic': 148, 'bp_diastolic': 96},
        flags: ['high_blood_pressure'],
        referral: true,
        hasFollowup: true,
      ),
      (
        idx: 4,
        benId: '${demoPrefix}ben_3',
        purpose: 'general_illness',
        daysAgo: 2,
        method: 'voice',
        durSecs: 49,
        payload: {'temperature_c': 38.4},
        flags: ['fever'],
        referral: false,
        hasFollowup: false,
      ),
      (
        idx: 5,
        benId: '${demoPrefix}ben_5',
        purpose: 'newborn_home_visit',
        daysAgo: 4,
        method: 'manual',
        durSecs: 0,
        payload: {'weight_kg': 3.1, 'temperature_c': 36.8},
        flags: [],
        referral: false,
        hasFollowup: false,
      ),
      (
        idx: 6,
        benId: '${demoPrefix}ben_2',
        purpose: 'anc_visit',
        daysAgo: 6,
        method: 'voice',
        durSecs: 58,
        payload: {'bp_systolic': 136, 'bp_diastolic': 88},
        flags: ['swelling'],
        referral: false,
        hasFollowup: true,
      ),
      (
        idx: 7,
        benId: '${demoPrefix}ben_1',
        purpose: 'newborn_home_visit',
        daysAgo: 8,
        method: 'voice',
        durSecs: 61,
        payload: {'weight_kg': 2.3, 'temperature_c': 36.6},
        flags: ['low_birth_weight'],
        referral: false,
        hasFollowup: false,
      ),
      (
        idx: 8,
        benId: '${demoPrefix}ben_3',
        purpose: 'general_illness',
        daysAgo: 11,
        method: 'voice',
        durSecs: 41,
        payload: {'temperature_c': 37.9},
        flags: ['cough'],
        referral: false,
        hasFollowup: false,
      ),
      (
        idx: 9,
        benId: '${demoPrefix}ben_4',
        purpose: 'ncd_screening',
        daysAgo: 13,
        method: 'voice',
        durSecs: 39,
        payload: {'bp_systolic': 152, 'bp_diastolic': 94},
        flags: ['high_blood_pressure'],
        referral: true,
        hasFollowup: false,
      ),
    ];

    visitSpecs.sort((a, b) => b.daysAgo.compareTo(a.daysAgo));
    for (final spec in visitSpecs) {
      final vid = '${demoPrefix}visit_${spec.idx}';
      if (existingVisitIds.contains(vid)) continue;
      final visitDay = refToday.subtract(Duration(days: spec.daysAgo));
      final startedDt = DateTime.utc(visitDay.year, visitDay.month, visitDay.day, 10);
      final confirmedDt = startedDt.add(Duration(seconds: spec.durSecs));
      final visitIso = DueEngine.formatIsoDate(visitDay);

      await localDb.confirmVisitV2(
        VisitRecord(
          id: vid,
          clientId: vid,
          beneficiaryId: spec.benId,
          workerId: workerId,
          visitTypeCode: spec.purpose,
          visitedAt: visitIso,
          payload: spec.payload,
          riskFlags: spec.flags,
          referralSuggested: spec.referral,
          inputMethod: spec.method,
          startedAt: startedDt.toIso8601String(),
          confirmedAt: confirmedDt.toIso8601String(),
          updatedAt: confirmedDt.toIso8601String(),
        ),
        actorId: workerId,
      );
      if (spec.hasFollowup) {
        await localDb.saveFollowupV2(
          id: '${demoPrefix}fu_${spec.idx}',
          visitId: vid,
          questionText: 'Demo follow-up clarification',
          answerText: 'Confirmed by worker',
        );
      }
      createdCount++;
    }

    // Set deterministic due_today (ben_5) and overdue (ben_6) anchors when seeded.
    final ben5 = await localDb.getBeneficiaryV2('${demoPrefix}ben_5');
    if (ben5 != null) {
      final bumpTime =
          now.add(const Duration(milliseconds: 5)).toIso8601String();
      await localDb.upsertBeneficiaryV2(
        BeneficiaryRecord(
          id: ben5.id,
          localCode: ben5.localCode,
          externalId: ben5.externalId,
          workerId: ben5.workerId,
          areaId: ben5.areaId,
          householdId: ben5.householdId,
          fullName: ben5.fullName,
          sex: ben5.sex,
          dob: ben5.dob,
          dobIsEstimated: ben5.dobIsEstimated,
          beneficiaryType: ben5.beneficiaryType,
          motherId: ben5.motherId,
          phoneEnc: ben5.phoneEnc,
          consentId: ben5.consentId,
          status: ben5.status,
          riskLevel: ben5.riskLevel,
          lastVisitAt: ben5.lastVisitAt,
          nextDueAt: DueEngine.formatIsoDate(refToday),
          createdAt: ben5.createdAt,
          updatedAt: bumpTime,
          version: ben5.version + 1,
        ),
        actorId: workerId,
      );
    }

    final ben6 = await localDb.getBeneficiaryV2('${demoPrefix}ben_6');
    if (ben6 != null) {
      final bumpTime =
          now.add(const Duration(milliseconds: 6)).toIso8601String();
      await localDb.upsertBeneficiaryV2(
        BeneficiaryRecord(
          id: ben6.id,
          localCode: ben6.localCode,
          externalId: ben6.externalId,
          workerId: ben6.workerId,
          areaId: ben6.areaId,
          householdId: ben6.householdId,
          fullName: ben6.fullName,
          sex: ben6.sex,
          dob: ben6.dob,
          dobIsEstimated: ben6.dobIsEstimated,
          beneficiaryType: ben6.beneficiaryType,
          motherId: ben6.motherId,
          phoneEnc: ben6.phoneEnc,
          consentId: ben6.consentId,
          status: ben6.status,
          riskLevel: ben6.riskLevel,
          lastVisitAt: ben6.lastVisitAt,
          nextDueAt: DueEngine.formatIsoDate(
            refToday.subtract(const Duration(days: 3)),
          ),
          createdAt: ben6.createdAt,
          updatedAt: bumpTime,
          version: ben6.version + 1,
        ),
        actorId: workerId,
      );
    }

    return createdCount;
  }

  static Future<int> clearDemoData(
    LocalDbService localDb, {
    required String workerId,
  }) {
    return localDb.clearDemoSeedData(workerId);
  }
}
