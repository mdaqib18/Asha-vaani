import 'package:asha_vaani/models/newborn_visit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses VisitTurnResponse matching SPEC section 7 & 10', () {
    final json = <String, dynamic>{
      'session_id': 'sess-123',
      'transcript': 'Beneficiary 1042, weight 2.5 kg hai, aur limb problem hai',
      'record': {
        'beneficiary_id': {
          'value': '1042',
          'confidence': 0.7,
          'source': 'speech',
          'needs_confirmation': true,
        },
        'baby_weight_kg': {
          'value': 2.5,
          'confidence': 0.9,
          'source': 'speech',
          'needs_confirmation': true,
        },
        'limb_abnormality': {
          'value': {'present': true, 'location': 'unspecified'},
          'confidence': 0.8,
          'source': 'speech',
          'needs_confirmation': false,
        },
        'risk_flags': ['limb_abnormality'],
        'referral_suggested': true,
      },
      'flags': [
        {'field': 'temperature_c', 'reason': 'missing_required'},
      ],
      'risk_flags': ['limb_abnormality'],
      'referral_suggested': true,
      'status': 'needs_followup',
      'followup': {
        'question_text': 'Temperature details are missing.',
        'question_audio_url': '/v1/audio/clip-1',
        'target_fields': ['temperature_c'],
        'followup_count': 1,
      },
    };

    final turn = VisitTurnResponse.fromJson(json);
    expect(turn.sessionId, 'sess-123');
    expect(turn.record.beneficiaryId?.value, '1042');
    expect(turn.record.beneficiaryId?.needsConfirmation, isTrue);
    expect(turn.record.babyWeightKg?.value, 2.5);
    expect(turn.record.limbAbnormality?.value?.present, isTrue);
    expect(turn.record.limbAbnormality?.value?.location, 'unspecified');
    expect(turn.flags.single.field, 'temperature_c');
    expect(turn.riskFlags, ['limb_abnormality']);
    expect(turn.referralSuggested, isTrue);
    expect(turn.status, 'needs_followup');
    expect(turn.followup?.questionAudioUrl, '/v1/audio/clip-1');
    expect(turn.followup?.followupCount, 1);
  });

  test('parses VisitSummary', () {
    final summary = VisitSummary.fromJson({
      'visit_id': 'v-1',
      'session_id': 's-1',
      'beneficiary_id': '1042',
      'visit_date': '2026-11-21',
      'risk_flags': ['low_birth_weight'],
      'referral_suggested': true,
      'status': 'saved',
      'updated_at': '2026-11-21T10:00:00Z',
    });

    expect(summary.visitId, 'v-1');
    expect(summary.beneficiaryId, '1042');
    expect(summary.riskFlags, ['low_birth_weight']);
    expect(summary.referralSuggested, isTrue);
    expect(summary.status, 'saved');
  });
}
