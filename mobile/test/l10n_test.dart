import 'package:asha_vaani/l10n/app_strings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('all localized strings and enums are non-empty across en, hi, kn', () {
    const fields = [
      'beneficiary_id',
      'baby_weight_kg',
      'temperature_c',
      'breastfeeding',
      'cord_status',
      'jaundice',
      'breathing_rate_per_min',
      'limb_abnormality',
      'danger_signs',
      'mother_notes',
      'notes',
    ];
    const flags = [
      'low_birth_weight',
      'fever',
      'hypothermia',
      'fast_breathing',
      'cord_infection',
      'not_feeding',
      'jaundice',
      'limb_abnormality',
      'danger_sign:convulsions',
    ];

    for (final lang in AppLanguage.values) {
      final s = AppStrings.of(lang);
      expect(s.appSubtitle.trim(), isNotEmpty);
      expect(s.selectWorker.trim(), isNotEmpty);
      expect(s.holdToSpeak.trim(), isNotEmpty);
      expect(s.referralBannerTitle.trim(), isNotEmpty);
      expect(s.confirmAndSave.trim(), isNotEmpty);
      expect(s.readBack.trim(), isNotEmpty);
      expect(s.friendlyError('NETWORK_ERROR').trim(), isNotEmpty);
      expect(s.friendlyError('TIMEOUT').trim(), isNotEmpty);
      expect(s.friendlyError('INVALID_AUDIO').trim(), isNotEmpty);

      for (final f in fields) {
        expect(s.fieldLabel(f).trim(), isNotEmpty);
      }
      for (final rf in flags) {
        expect(s.riskFlagLabel(rf).trim(), isNotEmpty);
      }
      for (final bf in const ['exclusive', 'partial', 'not_feeding', 'unknown']) {
        expect(s.breastfeedingLabel(bf).trim(), isNotEmpty);
      }
      for (final cs in const ['clean_dry', 'red_swollen', 'pus_discharge', 'unknown']) {
        expect(s.cordStatusLabel(cs).trim(), isNotEmpty);
      }
    }
  });
}
