import '../models/v2_models.dart';
import 'due_engine.dart';

/// Transliteration-tolerant offline duplicate detector matching backend rules (SPEC_V2 §5.4).
class DuplicateDetector {
  DuplicateDetector._();

  static const Set<String> _honorifics = {
    'smt',
    'shrimati',
    'shri',
    'sri',
    'mrs',
    'mr',
    'ms',
    'miss',
    'km',
    'kumari',
    'devi',
    'bai',
    'begum',
    'bibi',
    'w/o',
    'd/o',
    's/o',
    'c/o',
    'श्रीमती',
    'श्री',
    'कुमारी',
    'देवी',
  };

  static const List<(String, String)> _phoneticRules = [
    ('ee', 'i'),
    ('oo', 'u'),
    ('aa', 'a'),
    ('ph', 'f'),
    ('sh', 's'),
    ('kh', 'k'),
    ('gh', 'g'),
    ('bh', 'b'),
    ('dh', 'd'),
    ('th', 't'),
    ('jh', 'j'),
    ('ch', 'c'),
    ('v', 'w'),
    ('z', 'j'),
  ];

  static String _foldPhonetic(String token) {
    var folded = token;
    for (final rule in _phoneticRules) {
      folded = folded.replaceAll(rule.$1, rule.$2);
    }
    final buf = StringBuffer();
    String? prev;
    for (final rune in folded.runes) {
      final ch = String.fromCharCode(rune);
      if (ch != prev) {
        buf.write(ch);
        prev = ch;
      }
    }
    return buf.toString();
  }

  static String normalizeName(String name) {
    final lower = name.toLowerCase().trim().replaceAll(RegExp(r'[./_-]+'), ' ');
    final matches = RegExp(r'[^\s\d\p{P}\p{S}]+', unicode: true).allMatches(lower);
    final rawTokens = matches.map((m) => m.group(0)!).toList();
    final cleaned = <String>[];
    for (final token in rawTokens) {
      if (_honorifics.contains(token)) continue;
      cleaned.add(_foldPhonetic(token));
    }
    if (cleaned.isEmpty && rawTokens.isNotEmpty) {
      return rawTokens.map(_foldPhonetic).join(' ');
    }
    return cleaned.join(' ');
  }

  static String normalizePhone(String? phone) {
    if (phone == null) return '';
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    return digits.length > 10 ? digits.substring(digits.length - 10) : digits;
  }

  static int levenshteinDistance(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;

    final aRunes = a.runes.toList();
    final bRunes = b.runes.toList();
    var prev = List<int>.generate(bRunes.length + 1, (i) => i);

    for (var i = 0; i < aRunes.length; i++) {
      final curr = List<int>.filled(bRunes.length + 1, 0);
      curr[0] = i + 1;
      for (var j = 0; j < bRunes.length; j++) {
        final cost = aRunes[i] == bRunes[j] ? 0 : 1;
        final del = prev[j + 1] + 1;
        final ins = curr[j] + 1;
        final sub = prev[j] + cost;
        curr[j + 1] = [del, ins, sub].reduce((x, y) => x < y ? x : y);
      }
      prev = curr;
    }
    return prev.last;
  }

  static double nameSimilarity(String a, String b) {
    final na = normalizeName(a);
    final nb = normalizeName(b);
    if (na.isEmpty || nb.isEmpty) return 0.0;

    final compactA = na.replaceAll(' ', '');
    final compactB = nb.replaceAll(' ', '');
    final sortedA = (na.split(' ')..sort()).join();
    final sortedB = (nb.split(' ')..sort()).join();

    double ratio(String s1, String s2) {
      final denom = s1.length > s2.length ? s1.length : s2.length;
      if (denom == 0) return 0.0;
      return 1.0 - (levenshteinDistance(s1, s2) / denom);
    }

    final r1 = ratio(compactA, compactB);
    final r2 = ratio(sortedA, sortedB);
    return r1 > r2 ? r1 : r2;
  }

  static List<DuplicateCandidate> findCandidates({
    required String fullName,
    required String workerId,
    String? areaId,
    String? dob,
    String? phoneEnc,
    String? excludeId,
    required List<BeneficiaryRecord> existing,
    double nameThreshold = 0.78,
    int dobWindowDays = 366,
  }) {
    final candPhone = normalizePhone(phoneEnc);
    final candDob = DueEngine.parseIsoDate(dob);
    final matches = <DuplicateCandidate>[];

    for (final row in existing) {
      if (excludeId != null && row.id == excludeId) continue;
      if (row.status != 'active' || row.deletedAt != null) continue;
      if (areaId != null &&
          areaId.isNotEmpty &&
          row.areaId != null &&
          row.areaId!.isNotEmpty &&
          areaId != row.areaId) {
        continue;
      }
      if ((areaId == null || areaId.isEmpty || row.areaId == null || row.areaId!.isEmpty) &&
          workerId != row.workerId) {
        continue;
      }

      final sim = nameSimilarity(fullName, row.fullName);
      final rowPhone = normalizePhone(row.phoneEnc);
      final phoneMatch = candPhone.length >= 7 && rowPhone.isNotEmpty && candPhone == rowPhone;
      final rowDob = DueEngine.parseIsoDate(row.dob);
      final dobKnownBoth = candDob != null && rowDob != null;
      final dobClose =
          dobKnownBoth && candDob.difference(rowDob).inDays.abs() <= dobWindowDays;

      final reasons = <String>[];
      var isMatch = false;

      if (sim >= nameThreshold &&
          (dobClose || phoneMatch || (!dobKnownBoth && sim >= 0.88))) {
        isMatch = true;
        reasons.add('similar_name');
      } else if (phoneMatch && dobClose && sim >= 0.50) {
        isMatch = true;
        reasons.add('similar_name');
      }

      if (phoneMatch) reasons.add('same_phone');
      if (dobClose) reasons.add('dob_within_1y');

      if (isMatch) {
        final rawScore = phoneMatch && sim < 0.92 ? 0.92 : sim;
        final capped = rawScore > 1.0 ? 1.0 : rawScore;
        matches.add(
          DuplicateCandidate(
            beneficiary: row,
            score: double.parse(capped.toStringAsFixed(3)),
            reasons: reasons,
          ),
        );
      }
    }

    matches.sort((a, b) {
      final cmp = b.score.compareTo(a.score);
      return cmp != 0 ? cmp : a.beneficiary.localCode.compareTo(b.beneficiary.localCode);
    });
    return matches;
  }
}
