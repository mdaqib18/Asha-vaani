import '../l10n/app_strings.dart';
import '../services/due_engine.dart';

class VisitTypeField {
  const VisitTypeField({
    required this.key,
    required this.type,
    this.required = false,
    this.min,
    this.max,
    this.unit,
  });

  final String key;
  final String type;
  final bool required;
  final double? min;
  final double? max;
  final String? unit;

  factory VisitTypeField.fromJson(Map<String, dynamic> json) {
    return VisitTypeField(
      key: json['key'] as String? ?? '',
      type: json['type'] as String? ?? 'string',
      required: json['required'] as bool? ?? false,
      min: (json['min'] as num?)?.toDouble(),
      max: (json['max'] as num?)?.toDouble(),
      unit: json['unit'] as String?,
    );
  }
}

class VisitTypeSummary {
  const VisitTypeSummary({
    required this.code,
    required this.schemaVersion,
    required this.name,
    this.description = const {},
    this.appliesTo = const [],
    this.requiredFields = const [],
    this.fields = const [],
    this.voiceKeywords = const [],
    this.active = true,
  });

  final String code;
  final int schemaVersion;
  final Map<String, String> name;
  final Map<String, String> description;
  final List<String> appliesTo;
  final List<String> requiredFields;
  final List<VisitTypeField> fields;
  final List<String> voiceKeywords;
  final bool active;

  String localizedName(AppLanguage language) {
    return name[language.code] ?? name['en'] ?? code;
  }

  String localizedDescription(AppLanguage language) {
    return description[language.code] ?? description['en'] ?? '';
  }

  factory VisitTypeSummary.fromJson(Map<String, dynamic> json) {
    Map<String, String> parseMap(Object? raw) {
      if (raw is Map) {
        return raw.map((k, v) => MapEntry(k.toString(), v.toString()));
      }
      return const {};
    }

    List<String> parseStrings(Object? raw) {
      if (raw is List) return raw.map((e) => e.toString()).toList();
      return const [];
    }

    return VisitTypeSummary(
      code: json['code'] as String? ?? '',
      schemaVersion: json['schema_version'] as int? ?? 1,
      name: parseMap(json['name']),
      description: parseMap(json['description']),
      appliesTo: parseStrings(json['applies_to']),
      requiredFields: parseStrings(json['required_fields']),
      fields: ((json['fields'] as List<dynamic>?) ?? const [])
          .map((e) => VisitTypeField.fromJson(e as Map<String, dynamic>))
          .toList(),
      voiceKeywords: parseStrings(json['voice_keywords']),
      active: json['active'] as bool? ?? true,
    );
  }
}

class DetectedPurpose {
  const DetectedPurpose({
    required this.code,
    required this.confidence,
    required this.matchedKeyword,
  });

  final String code;
  final double confidence;
  final String matchedKeyword;

  factory DetectedPurpose.fromJson(Map<String, dynamic> json) {
    return DetectedPurpose(
      code: json['code'] as String? ?? '',
      confidence: (json['confidence'] as num? ?? 0.0).toDouble(),
      matchedKeyword: json['matched_keyword'] as String? ?? '',
    );
  }
}

class SuggestedPurposeResult {
  const SuggestedPurposeResult({
    required this.beneficiaryId,
    required this.suggestedCode,
    required this.reason,
    required this.otherCodes,
    this.detectedPurpose,
  });

  final String beneficiaryId;
  final String suggestedCode;
  final Map<String, String> reason;
  final List<String> otherCodes;
  final DetectedPurpose? detectedPurpose;

  String localizedReason(AppLanguage language) {
    return reason[language.code] ?? reason['en'] ?? '';
  }

  factory SuggestedPurposeResult.fromJson(Map<String, dynamic> json) {
    final rawReason = json['reason'];
    final reasonMap = rawReason is Map
        ? rawReason.map((k, v) => MapEntry(k.toString(), v.toString()))
        : <String, String>{};
    final detectedRaw = json['detected_purpose'];
    return SuggestedPurposeResult(
      beneficiaryId: json['beneficiary_id'] as String? ?? '',
      suggestedCode: json['suggested_code'] as String? ?? 'newborn_home_visit',
      reason: reasonMap,
      otherCodes: ((json['other_codes'] as List<dynamic>?) ?? const [])
          .map((e) => e.toString())
          .toList(),
      detectedPurpose: detectedRaw is Map<String, dynamic>
          ? DetectedPurpose.fromJson(detectedRaw)
          : null,
    );
  }
}

/// Offline-first mirror of the backend YAML visit-type registry (SPEC_V2 §4).
class BuiltInVisitTypes {
  BuiltInVisitTypes._();

  static const List<VisitTypeSummary> all = [
    VisitTypeSummary(
      code: 'newborn_home_visit',
      schemaVersion: 1,
      name: {
        'en': 'Newborn home visit',
        'hi': 'नवजात गृह भेंट',
        'kn': 'ನವಜಾತ ಮನೆ ಭೇಟಿ',
      },
      description: {
        'en': 'Postnatal newborn weight, temperature, feeding, cord, jaundice and breathing check.',
        'hi': 'नवजात का वजन, तापमान, स्तनपान, नाल, पीलिया और सांस की जांच।',
        'kn': 'ನವಜಾತ ಶಿಶುವಿನ ತೂಕ, ತಾಪಮಾನ, ಎದೆಹಾಲು, ಹೊಕ್ಕಳುಬಳ್ಳಿ, ಕಾಮಾಲೆ ಮತ್ತು ಉಸಿರಾಟ ಪರಿಶೀಲನೆ.',
      },
      appliesTo: ['newborn'],
      requiredFields: [
        'beneficiary_id',
        'baby_weight_kg',
        'temperature_c',
        'breastfeeding',
        'cord_status',
        'jaundice',
        'limb_abnormality',
      ],
      voiceKeywords: [
        'newborn home visit',
        'newborn',
        'hbnc',
        'baby weight',
        'नवजात',
        'नाल',
        'ನವಜಾತ',
        'ಶಿಶು',
      ],
    ),
    VisitTypeSummary(
      code: 'anc_visit',
      schemaVersion: 1,
      name: {
        'en': 'Antenatal check (ANC)',
        'hi': 'प्रसव पूर्व जांच (ANC)',
        'kn': 'ಗರ್ಭಿಣಿ ತಪಾಸಣೆ (ANC)',
      },
      description: {
        'en': 'Pregnancy check for gestation weeks, weight, BP, Hb, IFA tablets and danger signs.',
        'hi': 'गर्भावस्था के सप्ताह, वजन, बीपी, हीमोग्लोबिन, आयरन गोली और खतरे के लक्षण की जांच।',
        'kn': 'ಗರ್ಭಾವಸ್ಥೆಯ ವಾರಗಳು, ತೂಕ, ಬಿಪಿ, ಹಿಮೋಗ್ಲೋಬಿನ್, ಐಎಫ್‌ಎ ಮಾತ್ರೆ ಮತ್ತು ಅಪಾಯದ ಚಿಹ್ನೆಗಳ ಪರಿಶೀಲನೆ.',
      },
      appliesTo: ['pregnant_woman'],
      requiredFields: ['beneficiary_id', 'gestation_weeks', 'bp_systolic', 'bp_diastolic'],
      voiceKeywords: [
        'anc check',
        'antenatal',
        'pregnancy check',
        'pregnant',
        'garbhavati',
        'गर्भवती',
        'प्रसव पूर्व',
        'ಗರ್ಭಿಣಿ',
      ],
    ),
    VisitTypeSummary(
      code: 'general_illness',
      schemaVersion: 1,
      name: {
        'en': 'General illness check',
        'hi': 'सामान्य बीमारी जांच',
        'kn': 'ಸಾಮಾನ್ಯ ಅನಾರೋಗ್ಯ ತಪಾಸಣೆ',
      },
      description: {
        'en': 'Symptoms, fever duration, temperature, care given and referral check for any beneficiary.',
        'hi': 'किसी भी व्यक्ति के लक्षण, बुखार के दिन, तापमान, देखभाल और रेफरल की जांच।',
        'kn': 'ಯಾವುದೇ ವ್ಯಕ್ತಿಯ ಲಕ್ಷಣಗಳು, ಜ್ವರದ ದಿನಗಳು, ತಾಪಮಾನ, ಆರೈಕೆ ಮತ್ತು ರೆಫರಲ್ ಪರಿಶೀಲನೆ.',
      },
      appliesTo: ['newborn', 'pregnant_woman', 'pnc_mother', 'child_u5', 'adult', 'other'],
      requiredFields: ['beneficiary_id', 'symptoms', 'temperature_c'],
      voiceKeywords: [
        'general illness',
        'illness',
        'fever',
        'cough',
        'sick',
        'bukhar',
        'बुखार',
        'बीमारी',
        'ಜ್ವರ',
        'ಕೆಮ್ಮು',
        'ಅನಾರೋಗ್ಯ',
      ],
    ),
    VisitTypeSummary(
      code: 'ncd_screening',
      schemaVersion: 1,
      name: {
        'en': 'NCD screening (BP & Sugar)',
        'hi': 'बीपी और शुगर जांच (NCD)',
        'kn': 'ಬಿಪಿ ಮತ್ತು ಸಕ್ಕರೆ ತಪಾಸಣೆ (NCD)',
      },
      description: {
        'en': 'Adult check for blood pressure, random blood sugar, symptoms and tobacco use.',
        'hi': 'वयस्कों के ब्लड प्रेशर, ब्लड शुगर, लक्षण और तंबाकू उपयोग की जांच।',
        'kn': 'ವಯಸ್ಕರಿಗೆ ರಕ್ತದೊತ್ತಡ, ರಕ್ತದ ಸಕ್ಕರೆ, ಲಕ್ಷಣಗಳು ಮತ್ತು ತಂಬಾಕು ಬಳಕೆ ಪರಿಶೀಲನೆ.',
      },
      appliesTo: ['adult', 'other'],
      requiredFields: ['beneficiary_id', 'bp_systolic', 'bp_diastolic'],
      voiceKeywords: [
        'ncd screening',
        'blood pressure',
        'bp check',
        'sugar check',
        'blood sugar',
        'diabetes',
        'ncd',
        'बीपी',
        'ब्लड प्रेशर',
        'शुगर',
        'ಬಿಪಿ',
        'ರಕ್ತದೊತ್ತಡ',
        'ಸಕ್ಕರೆ',
      ],
    ),
  ];

  static VisitTypeSummary? findByCode(String code, [List<VisitTypeSummary>? list]) {
    for (final item in list ?? all) {
      if (item.code == code) return item;
    }
    return null;
  }

  static bool _isAsciiWordOnly(String s) =>
      RegExp(r'^[a-z0-9 ]+$').hasMatch(s);

  static DetectedPurpose? detectFromSpeech(
    String text, {
    List<VisitTypeSummary>? types,
  }) {
    final normalized = text.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.isEmpty) return null;

    final matches = <(int len, String code, String kw)>[];
    for (final item in types ?? all) {
      if (!item.active) continue;
      for (final kw in item.voiceKeywords) {
        final clean = kw.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
        if (clean.isEmpty) continue;
        final matched = _isAsciiWordOnly(clean)
            ? RegExp('(?<!\\w)${RegExp.escape(clean)}(?!\\w)')
                .hasMatch(normalized)
            : normalized.contains(clean);
        if (matched) {
          matches.add((clean.length, item.code, kw));
        }
      }
    }
    if (matches.isEmpty) return null;
    matches.sort((a, b) => b.$1.compareTo(a.$1));
    return DetectedPurpose(
      code: matches.first.$2,
      confidence: 0.9,
      matchedKeyword: matches.first.$3,
    );
  }

  static SuggestedPurposeResult suggestForBeneficiary({
    required String beneficiaryId,
    String beneficiaryType = 'newborn',
    String? dobIso,
    String? spokenHint,
    DateTime? today,
    List<VisitTypeSummary>? types,
  }) {
    final catalog = (types ?? all).where((e) => e.active).toList();
    final availableCodes = catalog.map((e) => e.code).toSet();
    final now = today ?? DateTime.now();
    final refToday = DateTime.utc(now.year, now.month, now.day);
    final btype = beneficiaryType.trim().toLowerCase();
    final parsedDob = DueEngine.parseIsoDate(dobIso);

    var suggested = 'general_illness';
    var reason = const {
      'en': 'General check or new symptoms reported',
      'hi': 'सामान्य जांच या नए लक्षण दर्ज करें',
      'kn': 'ಸಾಮಾನ್ಯ ತಪಾಸಣೆ ಅಥವಾ ಹೊಸ ಲಕ್ಷಣಗಳನ್ನು ದಾಖಲಿಸಿ',
    };

    if (btype == 'newborn') {
      final ageDays =
          parsedDob != null ? refToday.difference(parsedDob).inDays : null;
      if ((ageDays == null || ageDays <= 42) &&
          availableCodes.contains('newborn_home_visit')) {
        suggested = 'newborn_home_visit';
        int? nextDay;
        if (ageDays != null) {
          final safeAge = ageDays < 0 ? 0 : ageDays;
          for (final d in DueEngine.newbornScheduleDays) {
            if (d >= safeAge) {
              nextDay = d;
              break;
            }
          }
        }
        reason = nextDay != null
            ? {
                'en': 'Newborn day $nextDay visit is due',
                'hi': 'नवजात दिन $nextDay भेंट बाकी है',
                'kn': 'ನವಜಾತ ದಿನ $nextDay ಭೇಟಿ ಬಾಕಿ ಇದೆ',
              }
            : const {
                'en': 'Newborn home visit is due',
                'hi': 'नवजात गृह भेंट बाकी है',
                'kn': 'ನವಜಾತ ಮನೆ ಭೇಟಿ ಬಾಕಿ ಇದೆ',
              };
      }
    } else if (btype == 'pregnant_woman' &&
        availableCodes.contains('anc_visit')) {
      suggested = 'anc_visit';
      reason = const {
        'en': 'Antenatal check is due',
        'hi': 'प्रसव पूर्व जांच (ANC) बाकी है',
        'kn': 'ಗರ್ಭಿಣಿ ತಪಾಸಣೆ (ANC) ಬಾಕಿ ಇದೆ',
      };
    } else if ((btype == 'adult' || btype == 'other') &&
        availableCodes.contains('ncd_screening')) {
      suggested = 'ncd_screening';
      reason = const {
        'en': 'Routine BP and blood sugar screening',
        'hi': 'नियमित बीपी और ब्लड शुगर जांच',
        'kn': 'ನಿಯಮಿತ ಬಿಪಿ ಮತ್ತು ಸಕ್ಕರೆ ತಪಾಸಣೆ',
      };
    }

    final others = <String>[];
    for (final item in catalog) {
      if (item.code == suggested) continue;
      if (item.appliesTo.isEmpty || item.appliesTo.contains(btype)) {
        others.add(item.code);
      }
    }
    if (availableCodes.contains('general_illness') &&
        suggested != 'general_illness' &&
        !others.contains('general_illness')) {
      others.add('general_illness');
    }

    return SuggestedPurposeResult(
      beneficiaryId: beneficiaryId,
      suggestedCode: suggested,
      reason: reason,
      otherCodes: others,
      detectedPurpose:
          spokenHint != null ? detectFromSpeech(spokenHint, types: catalog) : null,
    );
  }
}
