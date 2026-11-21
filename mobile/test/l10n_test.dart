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
      expect(s.statusPlayingQuestion.trim(), isNotEmpty);
      expect(s.tapWhenDone.trim(), isNotEmpty);
      expect(s.replayQuestion.trim(), isNotEmpty);
      expect(s.skipToReview.trim(), isNotEmpty);
      expect(s.followupStep(1).trim(), isNotEmpty);
      expect(s.playingReadback.trim(), isNotEmpty);
      expect(s.savedOfflineTitle.trim(), isNotEmpty);
      expect(s.savedOfflineSubtitle.trim(), isNotEmpty);
      expect(s.offlineShowingCached.trim(), isNotEmpty);
      expect(s.pendingBadge.trim(), isNotEmpty);
      expect(s.readyToReviewBadge.trim(), isNotEmpty);
      expect(s.syncNow.trim(), isNotEmpty);
      expect(s.syncing.trim(), isNotEmpty);
      expect(s.pendingSyncBanner(2).trim(), isNotEmpty);
      expect(s.done.trim(), isNotEmpty);
      expect(s.supervisorTitle.trim(), isNotEmpty);
      expect(s.supervisorSubtitle.trim(), isNotEmpty);
      expect(s.supervisorEmpty.trim(), isNotEmpty);
      expect(s.openSupervisorView.trim(), isNotEmpty);
      expect(s.flaggedCountLabel(3).trim(), isNotEmpty);
      expect(s.workerIdLabel.trim(), isNotEmpty);
      expect(s.visitDetailsTitle.trim(), isNotEmpty);
      expect(s.demoConsentNotice.trim(), isNotEmpty);
      expect(s.homeTab.trim(), isNotEmpty);
      expect(s.insightsTab.trim(), isNotEmpty);
      expect(s.settingsTab.trim(), isNotEmpty);
      expect(s.workerCodeLabel.trim(), isNotEmpty);
      expect(s.pinLabel.trim(), isNotEmpty);
      expect(s.signInAction.trim(), isNotEmpty);
      expect(s.unlockAction.trim(), isNotEmpty);
      expect(s.pinLockChip.trim(), isNotEmpty);
      expect(s.pinLockOfflineChip.trim(), isNotEmpty);
      expect(s.greeting('Lakshmi').trim(), isNotEmpty);
      expect(s.dueTodayLabel.trim(), isNotEmpty);
      expect(s.doneTodayLabel.trim(), isNotEmpty);
      expect(s.needsAttentionLabel.trim(), isNotEmpty);
      expect(s.recordVisitAction.trim(), isNotEmpty);
      expect(s.dueAndOverdueTitle.trim(), isNotEmpty);
      expect(s.noVisitsDueTitle.trim(), isNotEmpty);
      expect(s.highContrastLabel.trim(), isNotEmpty);
      expect(s.privacyAndDataTitle.trim(), isNotEmpty);
      expect(s.signOutAction.trim(), isNotEmpty);
      expect(s.friendlyError('INVALID_CREDENTIALS').trim(), isNotEmpty);
      expect(s.friendlyError('OFFLINE_FIRST_LOGIN').trim(), isNotEmpty);
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
