/// Deterministic local follow-up due-date and risk-level engine (SPEC_V2 §4.3, §5.2).
class DueEngine {
  DueEngine._();

  // HBNC newborn home visit schedule offsets in days (# TODO(verify) with ANM/NHM).
  static const List<int> newbornScheduleDays = [3, 7, 14, 21, 28, 42];
  static const List<int> pncScheduleDays = [3, 7, 14, 42];

  static const Set<String> highRiskFlags = {
    'low_birth_weight',
    'hypothermia',
    'fever',
    'elevated_temperature',
    'fast_breathing',
    'not_feeding',
    'cord_infection',
    'jaundice_present',
    'danger_signs_present',
    'limb_abnormality_reported',
    'high_blood_pressure',
    'severe_anemia',
    'heavy_bleeding',
    'severe_acute_malnutrition',
    'persistent_fever',
    'critical_hyperglycemia',
  };

  static const Map<String, String> measurementUnits = {
    'baby_weight_kg': 'kg',
    'weight_kg': 'kg',
    'temperature_c': 'C',
    'breathing_rate_per_min': '/min',
    'gestation_weeks': 'weeks',
    'bp_systolic': 'mmHg',
    'bp_diastolic': 'mmHg',
    'hb_g_dl': 'g/dL',
    'muac_cm': 'cm',
    'random_blood_sugar_mg_dl': 'mg/dL',
    'ifa_tablets_taken': 'tablets',
  };

  static DateTime computeEdd(DateTime lmpDate) {
    return DateTime.utc(lmpDate.year, lmpDate.month, lmpDate.day)
        .add(const Duration(days: 280));
  }

  static DateTime? computeNextDueAt({
    required String beneficiaryType,
    DateTime? dob,
    DateTime? visitedAt,
    DateTime? lmpDate,
    int? intervalDays,
    DateTime? today,
  }) {
    final now = today ?? DateTime.now();
    final refToday = DateTime.utc(now.year, now.month, now.day);
    final btype = beneficiaryType.trim().toLowerCase();
    final dobDay = dob == null ? null : DateTime.utc(dob.year, dob.month, dob.day);
    final visitDay =
        visitedAt == null ? null : DateTime.utc(visitedAt.year, visitedAt.month, visitedAt.day);

    if (btype == 'newborn') {
      if (dobDay != null) {
        final anchor = visitDay ?? refToday;
        final ageDays = anchor.difference(dobDay).inDays < 0 ? 0 : anchor.difference(dobDay).inDays;
        for (final targetDay in newbornScheduleDays) {
          if (visitDay != null) {
            if (targetDay > ageDays) {
              return dobDay.add(Duration(days: targetDay));
            }
          } else {
            if (targetDay >= ageDays) {
              return dobDay.add(Duration(days: targetDay));
            }
          }
        }
        return null;
      }
      final days = intervalDays ?? 7;
      return visitDay != null ? visitDay.add(Duration(days: days)) : refToday;
    }

    if (btype == 'pregnant_woman') {
      final days = intervalDays ?? 30;
      if (visitDay != null) {
        final nextDate = visitDay.add(Duration(days: days));
        if (lmpDate != null) {
          final edd = computeEdd(lmpDate);
          if (nextDate.isAfter(edd.add(const Duration(days: 14)))) {
            return edd;
          }
        }
        return nextDate;
      }
      return refToday;
    }

    if (btype == 'pnc_mother') {
      if (dobDay != null) {
        final anchor = visitDay ?? refToday;
        final daysSince = anchor.difference(dobDay).inDays < 0 ? 0 : anchor.difference(dobDay).inDays;
        for (final targetDay in pncScheduleDays) {
          if (visitDay != null) {
            if (targetDay > daysSince) {
              return dobDay.add(Duration(days: targetDay));
            }
          } else {
            if (targetDay >= daysSince) {
              return dobDay.add(Duration(days: targetDay));
            }
          }
        }
        return null;
      }
      final days = intervalDays ?? 7;
      return visitDay != null ? visitDay.add(Duration(days: days)) : refToday;
    }

    if (btype == 'child_u5') {
      final days = intervalDays ?? 30;
      return visitDay != null ? visitDay.add(Duration(days: days)) : refToday;
    }

    if (intervalDays != null && intervalDays > 0) {
      return (visitDay ?? refToday).add(Duration(days: intervalDays));
    }
    return null;
  }

  static String deriveRiskLevel(
    List<String> riskFlags, {
    bool referralSuggested = false,
    Map<String, String>? severities,
  }) {
    if (referralSuggested) return 'high';
    final sev = severities ?? const {};
    for (final flag in riskFlags) {
      if (sev[flag] == 'high' || highRiskFlags.contains(flag)) {
        return 'high';
      }
    }
    if (riskFlags.isNotEmpty ||
        sev.values.any((s) => s == 'watch' || s == 'medium')) {
      return 'watch';
    }
    return 'none';
  }

  static DateTime? parseIsoDate(String? raw) {
    if (raw == null || raw.length < 10) return null;
    return DateTime.tryParse(raw.substring(0, 10));
  }

  static String formatIsoDate(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static List<(String key, double value, String unit)> extractNumericMeasurements(
    Map<String, dynamic> payload,
  ) {
    final out = <(String, double, String)>[];
    for (final entry in measurementUnits.entries) {
      var raw = payload[entry.key];
      if (raw is Map) {
        raw = raw['value'];
      }
      if (raw == null || raw is bool) continue;
      if (raw is num) {
        out.add((entry.key, raw.toDouble(), entry.value));
      } else if (raw is String) {
        final parsed = double.tryParse(raw.trim());
        if (parsed != null) {
          out.add((entry.key, parsed, entry.value));
        }
      }
    }
    return out;
  }
}
