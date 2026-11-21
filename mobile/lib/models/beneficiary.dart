import '../services/due_engine.dart';
import 'newborn_visit.dart';
import 'v2_models.dart';

class Beneficiary {
  const Beneficiary({
    required this.id,
    required this.label,
    this.uuid,
    this.beneficiaryType = 'newborn',
    this.sex = 'unknown',
    this.dob,
    this.dobIsEstimated = false,
    this.area,
    this.motherId,
    this.phoneMasked,
    this.phoneLocal,
    this.riskLevel = 'none',
    this.nextDueAt,
    this.lastVisitAt,
    this.consentRecorded = false,
    this.eddDate,
    this.localOnly = false,
  });

  final String id;
  final String label;
  final String? uuid;
  final String beneficiaryType;
  final String sex;
  final String? dob;
  final bool dobIsEstimated;
  final String? area;
  final String? motherId;
  final String? phoneMasked;
  final String? phoneLocal;
  final String riskLevel;
  final String? nextDueAt;
  final String? lastVisitAt;
  final bool consentRecorded;
  final String? eddDate;
  final bool localOnly;

  bool get hasPhone =>
      (phoneLocal != null && phoneLocal!.isNotEmpty) ||
      (phoneMasked != null && phoneMasked!.isNotEmpty);

  static String? maskPhone(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 4) return '••••';
    final last4 = digits.substring(digits.length - 4);
    final maskLen = (digits.length - 4).clamp(4, 6);
    return '${'•' * maskLen}$last4';
  }

  factory Beneficiary.fromJson(Map<String, dynamic> json) {
    final localCode =
        json['local_code']?.toString() ?? json['id']?.toString() ?? '';
    final fullName =
        json['full_name']?.toString() ?? json['label']?.toString() ?? '';
    return Beneficiary(
      id: localCode,
      label: fullName,
      uuid: json['uuid']?.toString(),
      beneficiaryType: json['beneficiary_type']?.toString() ?? 'newborn',
      sex: json['sex']?.toString() ?? 'unknown',
      dob: json['dob']?.toString(),
      dobIsEstimated: json['dob_is_estimated'] as bool? ?? false,
      area: json['area_name']?.toString() ?? json['area_id']?.toString(),
      motherId: json['mother_id']?.toString(),
      phoneMasked: json['phone_masked']?.toString(),
      riskLevel: json['risk_level']?.toString() ?? 'none',
      nextDueAt: json['next_due_at']?.toString(),
      lastVisitAt: json['last_visit_at']?.toString(),
      consentRecorded: (json['consent_id']?.toString() ?? '').isNotEmpty,
      eddDate: json['edd_date']?.toString(),
    );
  }

  factory Beneficiary.fromV2Record(
    BeneficiaryRecord record, {
    String? eddDate,
    bool localOnly = false,
  }) {
    return Beneficiary(
      id: record.localCode,
      label: record.fullName,
      uuid: record.id,
      beneficiaryType: record.beneficiaryType,
      sex: record.sex,
      dob: record.dob,
      dobIsEstimated: record.dobIsEstimated,
      area: record.areaId,
      motherId: record.motherId,
      phoneMasked: maskPhone(record.phoneEnc),
      phoneLocal: record.phoneEnc,
      riskLevel: record.riskLevel,
      nextDueAt: record.nextDueAt,
      lastVisitAt: record.lastVisitAt,
      consentRecorded: (record.consentId ?? '').isNotEmpty,
      eddDate: eddDate,
      localOnly: localOnly,
    );
  }

  Beneficiary copyWith({
    String? label,
    String? uuid,
    String? beneficiaryType,
    String? sex,
    String? dob,
    bool? dobIsEstimated,
    String? area,
    String? motherId,
    String? phoneMasked,
    String? phoneLocal,
    String? riskLevel,
    String? nextDueAt,
    String? lastVisitAt,
    bool? consentRecorded,
    String? eddDate,
    bool? localOnly,
  }) {
    return Beneficiary(
      id: id,
      label: label ?? this.label,
      uuid: uuid ?? this.uuid,
      beneficiaryType: beneficiaryType ?? this.beneficiaryType,
      sex: sex ?? this.sex,
      dob: dob ?? this.dob,
      dobIsEstimated: dobIsEstimated ?? this.dobIsEstimated,
      area: area ?? this.area,
      motherId: motherId ?? this.motherId,
      phoneMasked: phoneMasked ?? this.phoneMasked,
      phoneLocal: phoneLocal ?? this.phoneLocal,
      riskLevel: riskLevel ?? this.riskLevel,
      nextDueAt: nextDueAt ?? this.nextDueAt,
      lastVisitAt: lastVisitAt ?? this.lastVisitAt,
      consentRecorded: consentRecorded ?? this.consentRecorded,
      eddDate: eddDate ?? this.eddDate,
      localOnly: localOnly ?? this.localOnly,
    );
  }

  String ageSummary() {
    final parsedDob = DueEngine.parseIsoDate(dob);
    if (parsedDob == null) return '';
    final days = DateTime.now().difference(parsedDob).inDays;
    if (days < 0) return '';
    if (days <= 45) return '$days d';
    if (days < 730) return '${(days / 30).floor()} mo';
    return '${(days / 365).floor()} yr';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        if (uuid != null) 'uuid': uuid,
        'beneficiary_type': beneficiaryType,
        'sex': sex,
        if (dob != null) 'dob': dob,
        'dob_is_estimated': dobIsEstimated,
        if (area != null) 'area_name': area,
        'risk_level': riskLevel,
        if (nextDueAt != null) 'next_due_at': nextDueAt,
      };
}

class BeneficiaryCreatePayload {
  const BeneficiaryCreatePayload({
    required this.workerId,
    required this.fullName,
    required this.beneficiaryType,
    this.sex = 'unknown',
    this.dob,
    this.dobIsEstimated = false,
    this.areaId,
    this.areaNote,
    this.motherId,
    this.phone,
    this.lmpDate,
    this.pregnancyMonths,
    this.consentGiven = true,
    this.consentGivenBy = 'self',
    this.consentMethod = 'verbal',
    this.beneficiaryUuid,
    this.localCode,
  });

  final String workerId;
  final String fullName;
  final String beneficiaryType;
  final String sex;
  final String? dob;
  final bool dobIsEstimated;
  final String? areaId;
  final String? areaNote;
  final String? motherId;
  final String? phone;
  final String? lmpDate;
  final int? pregnancyMonths;
  final bool consentGiven;
  final String consentGivenBy;
  final String consentMethod;
  final String? beneficiaryUuid;
  final String? localCode;

  Map<String, dynamic> toJson() => {
        'worker_id': workerId,
        'full_name': fullName.trim(),
        'beneficiary_type': beneficiaryType,
        'sex': sex,
        if (dob != null && dob!.isNotEmpty) 'dob': dob,
        'dob_is_estimated': dobIsEstimated,
        if (areaId != null && areaId!.isNotEmpty) 'area_id': areaId,
        if (areaNote != null && areaNote!.isNotEmpty) 'area_note': areaNote,
        if (motherId != null && motherId!.isNotEmpty) 'mother_id': motherId,
        if (phone != null && phone!.isNotEmpty) 'phone': phone,
        if (lmpDate != null && lmpDate!.isNotEmpty) 'lmp_date': lmpDate,
        if (pregnancyMonths != null) 'pregnancy_months': pregnancyMonths,
        'consent_given': consentGiven,
        'consent_given_by': consentGivenBy,
        'consent_method': consentMethod,
        if (beneficiaryUuid != null) 'beneficiary_id': beneficiaryUuid,
        if (localCode != null) 'local_code': localCode,
      };
}

class DuplicateMatchItem {
  const DuplicateMatchItem({
    required this.beneficiaryId,
    required this.localCode,
    required this.fullName,
    this.dob,
    required this.score,
    this.reasons = const [],
  });

  final String beneficiaryId;
  final String localCode;
  final String fullName;
  final String? dob;
  final double score;
  final List<String> reasons;

  factory DuplicateMatchItem.fromJson(Map<String, dynamic> json) {
    return DuplicateMatchItem(
      beneficiaryId: json['beneficiary_id']?.toString() ?? '',
      localCode: json['local_code']?.toString() ?? '',
      fullName: json['full_name']?.toString() ?? '',
      dob: json['dob']?.toString(),
      score: (json['score'] as num? ?? 0).toDouble(),
      reasons: ((json['reasons'] as List<dynamic>?) ?? const [])
          .map((e) => e.toString())
          .toList(),
    );
  }
}

class BeneficiarySpeechDraft {
  const BeneficiarySpeechDraft({
    required this.fullName,
    this.beneficiaryType = 'other',
    this.sex = 'unknown',
    this.dob,
    this.dobIsEstimated = false,
    this.ageYears,
    this.ageDays,
    this.pregnancyMonths,
    this.lmpDate,
    this.eddDate,
    this.areaNote,
    this.phone,
  });

  final String fullName;
  final String beneficiaryType;
  final String sex;
  final String? dob;
  final bool dobIsEstimated;
  final int? ageYears;
  final int? ageDays;
  final int? pregnancyMonths;
  final String? lmpDate;
  final String? eddDate;
  final String? areaNote;
  final String? phone;

  factory BeneficiarySpeechDraft.fromJson(Map<String, dynamic> json) {
    return BeneficiarySpeechDraft(
      fullName: json['full_name']?.toString() ?? '',
      beneficiaryType: json['beneficiary_type']?.toString() ?? 'other',
      sex: json['sex']?.toString() ?? 'unknown',
      dob: json['dob']?.toString(),
      dobIsEstimated: json['dob_is_estimated'] as bool? ?? false,
      ageYears: json['age_years'] as int?,
      ageDays: json['age_days'] as int?,
      pregnancyMonths: json['pregnancy_months'] as int?,
      lmpDate: json['lmp_date']?.toString(),
      eddDate: json['edd_date']?.toString(),
      areaNote: json['area_note']?.toString(),
      phone: json['phone']?.toString(),
    );
  }
}

class BeneficiaryAudioExtractResult {
  const BeneficiaryAudioExtractResult({
    required this.transcript,
    required this.draft,
    this.duplicateCandidates = const [],
  });

  final String transcript;
  final BeneficiarySpeechDraft draft;
  final List<DuplicateMatchItem> duplicateCandidates;

  factory BeneficiaryAudioExtractResult.fromJson(Map<String, dynamic> json) {
    final draftMap = json['draft'] as Map<String, dynamic>? ?? const {};
    final dups = (json['duplicate_candidates'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(DuplicateMatchItem.fromJson)
        .toList();
    return BeneficiaryAudioExtractResult(
      transcript: json['transcript']?.toString() ?? '',
      draft: BeneficiarySpeechDraft.fromJson(draftMap),
      duplicateCandidates: dups,
    );
  }
}

class MeasurementPoint {
  const MeasurementPoint({
    required this.key,
    required this.valueNum,
    required this.unit,
    required this.measuredAt,
  });

  final String key;
  final double valueNum;
  final String unit;
  final String measuredAt;

  factory MeasurementPoint.fromJson(Map<String, dynamic> json) {
    return MeasurementPoint(
      key: json['key']?.toString() ?? '',
      valueNum: (json['value_num'] as num? ?? 0).toDouble(),
      unit: json['unit']?.toString() ?? '',
      measuredAt: json['measured_at']?.toString() ?? '',
    );
  }
}

class BeneficiaryProfileVisits {
  const BeneficiaryProfileVisits({
    required this.beneficiaryId,
    this.visits = const [],
    this.measurements = const [],
  });

  final String beneficiaryId;
  final List<VisitSummary> visits;
  final List<MeasurementPoint> measurements;

  factory BeneficiaryProfileVisits.fromJson(Map<String, dynamic> json) {
    final visits = (json['visits'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(VisitSummary.fromJson)
        .toList();
    final measurements = (json['measurements'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(MeasurementPoint.fromJson)
        .toList();
    return BeneficiaryProfileVisits(
      beneficiaryId: json['beneficiary_id']?.toString() ?? '',
      visits: visits,
      measurements: measurements,
    );
  }
}

class AshaProfile {
  const AshaProfile({required this.id, required this.name, required this.area});

  final String id;
  final String name;
  final String area;

  static const List<AshaProfile> defaults = [
    AshaProfile(
      id: 'asha_001',
      name: 'Sunita Devi',
      area: 'Sub-center A (Synthetic)',
    ),
    AshaProfile(
      id: 'asha_002',
      name: 'Meena Kumari',
      area: 'Sub-center B (Synthetic)',
    ),
  ];

  static AshaProfile byId(String? id) {
    return defaults.firstWhere(
      (profile) => profile.id == id,
      orElse: () => defaults.first,
    );
  }
}

class LoginResult {
  const LoginResult({required this.token, required this.profile});

  final String token;
  final AshaProfile profile;

  factory LoginResult.fromJson(Map<String, dynamic> json) {
    final worker = json['worker'] as Map<String, dynamic>? ?? const {};
    return LoginResult(
      token: json['token']?.toString() ?? '',
      profile: AshaProfile(
        id: worker['id']?.toString() ?? '',
        name: worker['name']?.toString() ?? '',
        area: worker['area']?.toString() ?? '',
      ),
    );
  }
}
