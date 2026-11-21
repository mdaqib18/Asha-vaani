class ExtractedField<T> {
  const ExtractedField({
    required this.value,
    this.confidence = 1.0,
    this.source = 'speech',
    this.needsConfirmation = false,
  });

  final T? value;
  final double confidence;
  final String source;
  final bool needsConfirmation;

  static ExtractedField<T>? fromJson<T>(
    dynamic json,
    T Function(dynamic raw) parseValue,
  ) {
    if (json is! Map<String, dynamic>) return null;
    final rawVal = json['value'];
    return ExtractedField<T>(
      value: rawVal == null ? null : parseValue(rawVal),
      confidence: (json['confidence'] as num?)?.toDouble() ?? 1.0,
      source: json['source'] as String? ?? 'speech',
      needsConfirmation: json['needs_confirmation'] as bool? ?? false,
    );
  }
}

class LimbAbnormality {
  const LimbAbnormality({
    required this.present,
    this.location,
    this.description,
  });

  final bool present;
  final String? location;
  final String? description;

  factory LimbAbnormality.fromJson(Map<String, dynamic> json) {
    return LimbAbnormality(
      present: json['present'] as bool? ?? false,
      location: json['location'] as String?,
      description: json['description'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'present': present,
      if (location != null) 'location': location,
      if (description != null) 'description': description,
    };
  }
}

class NewbornVisitRecord {
  const NewbornVisitRecord({
    this.beneficiaryId,
    this.visitDate,
    this.babyWeightKg,
    this.temperatureC,
    this.breastfeeding,
    this.cordStatus,
    this.jaundice,
    this.breathingRatePerMin,
    this.limbAbnormality,
    this.dangerSigns,
    this.motherNotes,
    this.notes,
    this.riskFlags = const [],
    this.referralSuggested = false,
  });

  final ExtractedField<String>? beneficiaryId;
  final String? visitDate;
  final ExtractedField<double>? babyWeightKg;
  final ExtractedField<double>? temperatureC;
  final ExtractedField<String>? breastfeeding;
  final ExtractedField<String>? cordStatus;
  final ExtractedField<bool>? jaundice;
  final ExtractedField<int>? breathingRatePerMin;
  final ExtractedField<LimbAbnormality>? limbAbnormality;
  final ExtractedField<List<String>>? dangerSigns;
  final ExtractedField<String>? motherNotes;
  final ExtractedField<String>? notes;
  final List<String> riskFlags;
  final bool referralSuggested;

  factory NewbornVisitRecord.fromJson(Map<String, dynamic> json) {
    return NewbornVisitRecord(
      beneficiaryId: ExtractedField.fromJson(
        json['beneficiary_id'],
        (v) => v.toString(),
      ),
      visitDate: json['visit_date'] as String?,
      babyWeightKg: ExtractedField.fromJson(
        json['baby_weight_kg'],
        (v) => (v as num).toDouble(),
      ),
      temperatureC: ExtractedField.fromJson(
        json['temperature_c'],
        (v) => (v as num).toDouble(),
      ),
      breastfeeding: ExtractedField.fromJson(
        json['breastfeeding'],
        (v) => v.toString(),
      ),
      cordStatus: ExtractedField.fromJson(
        json['cord_status'],
        (v) => v.toString(),
      ),
      jaundice: ExtractedField.fromJson(
        json['jaundice'],
        (v) => v as bool,
      ),
      breathingRatePerMin: ExtractedField.fromJson(
        json['breathing_rate_per_min'],
        (v) => (v as num).toInt(),
      ),
      limbAbnormality: ExtractedField.fromJson(
        json['limb_abnormality'],
        (v) => LimbAbnormality.fromJson(v as Map<String, dynamic>),
      ),
      dangerSigns: ExtractedField.fromJson(
        json['danger_signs'],
        (v) => (v as List<dynamic>).map((e) => e.toString()).toList(),
      ),
      motherNotes: ExtractedField.fromJson(
        json['mother_notes'],
        (v) => v.toString(),
      ),
      notes: ExtractedField.fromJson(
        json['notes'],
        (v) => v.toString(),
      ),
      riskFlags: (json['risk_flags'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      referralSuggested: json['referral_suggested'] as bool? ?? false,
    );
  }
}

class ValidationFlag {
  const ValidationFlag({required this.field, required this.reason});

  final String field;
  final String reason;

  factory ValidationFlag.fromJson(Map<String, dynamic> json) {
    return ValidationFlag(
      field: json['field'] as String? ?? '',
      reason: json['reason'] as String? ?? '',
    );
  }
}

class FollowupPayload {
  const FollowupPayload({
    required this.questionText,
    this.questionAudioUrl,
    this.targetFields = const [],
    this.followupCount = 0,
  });

  final String questionText;
  final String? questionAudioUrl;
  final List<String> targetFields;
  final int followupCount;

  factory FollowupPayload.fromJson(Map<String, dynamic> json) {
    return FollowupPayload(
      questionText: json['question_text'] as String? ?? '',
      questionAudioUrl: json['question_audio_url'] as String?,
      targetFields: (json['target_fields'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      followupCount: (json['followup_count'] as num?)?.toInt() ?? 0,
    );
  }
}

class VisitTurnResponse {
  const VisitTurnResponse({
    required this.sessionId,
    required this.transcript,
    required this.record,
    this.flags = const [],
    this.riskFlags = const [],
    this.referralSuggested = false,
    required this.status,
    this.followup,
  });

  final String sessionId;
  final String transcript;
  final NewbornVisitRecord record;
  final List<ValidationFlag> flags;
  final List<String> riskFlags;
  final bool referralSuggested;
  final String status;
  final FollowupPayload? followup;

  factory VisitTurnResponse.fromJson(Map<String, dynamic> json) {
    return VisitTurnResponse(
      sessionId: json['session_id'] as String? ?? '',
      transcript: json['transcript'] as String? ?? '',
      record: NewbornVisitRecord.fromJson(
        json['record'] as Map<String, dynamic>? ?? const {},
      ),
      flags: (json['flags'] as List<dynamic>?)
              ?.map((e) => ValidationFlag.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      riskFlags: (json['risk_flags'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      referralSuggested: json['referral_suggested'] as bool? ?? false,
      status: json['status'] as String? ?? 'ready_to_confirm',
      followup: json['followup'] is Map<String, dynamic>
          ? FollowupPayload.fromJson(json['followup'] as Map<String, dynamic>)
          : null,
    );
  }
}

class RecordPatchResponse {
  const RecordPatchResponse({
    required this.sessionId,
    required this.record,
    this.flags = const [],
    this.riskFlags = const [],
    this.referralSuggested = false,
    required this.status,
  });

  final String sessionId;
  final NewbornVisitRecord record;
  final List<ValidationFlag> flags;
  final List<String> riskFlags;
  final bool referralSuggested;
  final String status;

  factory RecordPatchResponse.fromJson(Map<String, dynamic> json) {
    return RecordPatchResponse(
      sessionId: json['session_id'] as String? ?? '',
      record: NewbornVisitRecord.fromJson(
        json['record'] as Map<String, dynamic>? ?? const {},
      ),
      flags: (json['flags'] as List<dynamic>?)
              ?.map((e) => ValidationFlag.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      riskFlags: (json['risk_flags'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      referralSuggested: json['referral_suggested'] as bool? ?? false,
      status: json['status'] as String? ?? 'ready_to_confirm',
    );
  }
}

class ReadbackResponse {
  const ReadbackResponse({required this.text, this.audioUrl});

  final String text;
  final String? audioUrl;

  factory ReadbackResponse.fromJson(Map<String, dynamic> json) {
    return ReadbackResponse(
      text: json['text'] as String? ?? '',
      audioUrl: json['audio_url'] as String?,
    );
  }
}

class VisitSummary {
  const VisitSummary({
    this.visitId,
    required this.sessionId,
    this.beneficiaryId,
    this.visitDate,
    this.riskFlags = const [],
    this.referralSuggested = false,
    required this.status,
    required this.updatedAt,
  });

  final String? visitId;
  final String sessionId;
  final String? beneficiaryId;
  final String? visitDate;
  final List<String> riskFlags;
  final bool referralSuggested;
  final String status;
  final String updatedAt;

  factory VisitSummary.fromJson(Map<String, dynamic> json) {
    return VisitSummary(
      visitId: json['visit_id'] as String?,
      sessionId: json['session_id'] as String? ?? '',
      beneficiaryId: json['beneficiary_id'] as String?,
      visitDate: json['visit_date'] as String?,
      riskFlags: (json['risk_flags'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      referralSuggested: json['referral_suggested'] as bool? ?? false,
      status: json['status'] as String? ?? 'saved',
      updatedAt: json['updated_at'] as String? ?? '',
    );
  }
}
