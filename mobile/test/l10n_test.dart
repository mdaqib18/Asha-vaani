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
      expect(s.selectVisitPurposeTitle.trim(), isNotEmpty);
      expect(s.suggestedPurposeLabel.trim(), isNotEmpty);
      expect(s.otherPurposesTitle.trim(), isNotEmpty);
      expect(s.continueWithPurposeAction.trim(), isNotEmpty);
      expect(s.purposeVoiceHintLabel.trim(), isNotEmpty);
      expect(s.purposeVoiceHintPlaceholder.trim(), isNotEmpty);
      expect(s.detectedPurposeBanner('ANC').trim(), isNotEmpty);
      expect(s.switchPurposeAction('ANC').trim(), isNotEmpty);
      expect(s.offlineRegistryNotice.trim(), isNotEmpty);
      expect(s.noMatchingPurposesTitle.trim(), isNotEmpty);
      expect(s.visitPurposeChipLabel.trim(), isNotEmpty);
      expect(s.filterAll.trim(), isNotEmpty);
      expect(s.filterPregnant.trim(), isNotEmpty);
      expect(s.filterNewborns.trim(), isNotEmpty);
      expect(s.filterChildren.trim(), isNotEmpty);
      expect(s.filterOthers.trim(), isNotEmpty);
      expect(s.filterHighRisk.trim(), isNotEmpty);
      expect(s.addBeneficiaryAction.trim(), isNotEmpty);
      expect(s.speakToAddTitle.trim(), isNotEmpty);
      expect(s.beneficiaryWhoStep.trim(), isNotEmpty);
      expect(s.beneficiaryWhereStep.trim(), isNotEmpty);
      expect(s.beneficiaryConsentStep.trim(), isNotEmpty);
      expect(s.consentRequiredCheckbox.trim(), isNotEmpty);
      expect(s.possibleDuplicateTitle.trim(), isNotEmpty);
      expect(s.recordFirstVisitNowAction.trim(), isNotEmpty);
      expect(s.tapToRevealAction.trim(), isNotEmpty);
      expect(s.visitTimelineTitle.trim(), isNotEmpty);
      expect(s.beneficiaryTypeDisplay('pregnant_woman').trim(), isNotEmpty);
      expect(s.periodToday.trim(), isNotEmpty);
      expect(s.period7Days.trim(), isNotEmpty);
      expect(s.period30Days.trim(), isNotEmpty);
      expect(s.demoDataBadge.trim(), isNotEmpty);
      expect(s.coverageMetric.trim(), isNotEmpty);
      expect(s.referralsMetric.trim(), isNotEmpty);
      expect(s.dueOverdueMetric.trim(), isNotEmpty);
      expect(s.avgRecordTimeMetric.trim(), isNotEmpty);
      expect(s.voiceShareMetric.trim(), isNotEmpty);
      expect(s.followupRateMetric.trim(), isNotEmpty);
      expect(s.estTimeSavedMetric.trim(), isNotEmpty);
      expect(s.insightsTelemetryTitle.trim(), isNotEmpty);
      expect(s.visitsPerDayTitle.trim(), isNotEmpty);
      expect(s.visitsPerDayEmpty.trim(), isNotEmpty);
      expect(s.visitsByPurposeTitle.trim(), isNotEmpty);
      expect(s.visitsByPurposeEmpty.trim(), isNotEmpty);
      expect(s.riskBreakdownTitle.trim(), isNotEmpty);
      expect(s.riskBreakdownEmpty.trim(), isNotEmpty);
      expect(s.dueListCompactTitle.trim(), isNotEmpty);
      expect(s.dueListEmpty.trim(), isNotEmpty);
      expect(s.loadDemoDataAction.trim(), isNotEmpty);
      expect(s.clearDemoDataAction.trim(), isNotEmpty);
      expect(s.demoDataNotice.trim(), isNotEmpty);
      expect(s.visitsPerDaySummary(4, 1, 7).trim(), isNotEmpty);
      expect(s.visitsByPurposeSummary(2, 'ANC').trim(), isNotEmpty);
      expect(s.riskBreakdownSummary(3, 'Fever').trim(), isNotEmpty);
      expect(s.dueListSummary(1, 2).trim(), isNotEmpty);
      expect(s.avgSecondsFormat(45).trim(), isNotEmpty);
      expect(s.minutesSavedValue(4.2, 21).trim(), isNotEmpty);
      expect(s.paperBaselineLabel.trim(), isNotEmpty);
      expect(s.paperBaselineUnset.trim(), isNotEmpty);
      expect(s.paperBaselineSubtitle.trim(), isNotEmpty);
      expect(s.paperBaselineHint.trim(), isNotEmpty);
      expect(s.clearBaselineAction.trim(), isNotEmpty);
      expect(s.riskFlagLabel('high_blood_pressure').trim(), isNotEmpty);
      expect(s.encryptedOnDeviceChip.trim(), isNotEmpty);
      expect(s.pinProtectedChip.trim(), isNotEmpty);
      expect(s.unlockWithBiometricAction.trim(), isNotEmpty);
      expect(s.biometricReason.trim(), isNotEmpty);
      expect(s.biometricUnlockLabel.trim(), isNotEmpty);
      expect(s.autoLockLabel.trim(), isNotEmpty);
      expect(s.autoLockOptionSeconds(60).trim(), isNotEmpty);
      expect(s.screenshotProtectionDevLabel.trim(), isNotEmpty);
      expect(s.screenshotProtectionDevSubtitle.trim(), isNotEmpty);
      expect(s.encryptedSyncedLabel('Synced').trim(), isNotEmpty);
      expect(s.syncedJustNowLabel.trim(), isNotEmpty);
      expect(s.syncedMinutesAgo(2).trim(), isNotEmpty);
      expect(s.visitConsentTitle.trim(), isNotEmpty);
      expect(s.visitConsentCheckbox.trim(), isNotEmpty);
      expect(s.consentRecordedBadge.trim(), isNotEmpty);
      expect(s.externalIdLabel.trim(), isNotEmpty);
      expect(s.visitAuditLine('Lakshmi', '2026-11-22', 1).trim(), isNotEmpty);
      expect(s.securityStatusTitle.trim(), isNotEmpty);
      expect(s.runAudioCleanupAction.trim(), isNotEmpty);
      expect(s.audioCleanupResult(2).trim(), isNotEmpty);
      expect(s.privacyCollectedBody.trim(), isNotEmpty);
      expect(s.privacyStorageBody.trim(), isNotEmpty);
      expect(s.privacyRetentionBody.trim(), isNotEmpty);
      expect(s.privacyAccessBody.trim(), isNotEmpty);
      expect(s.privacyDeletionBody.trim(), isNotEmpty);
      expect(s.liveCaptionsTitle.trim(), isNotEmpty);
      expect(s.liveCaptionsPlaceholder.trim(), isNotEmpty);
      expect(s.liveCaptionsPausedNotice.trim(), isNotEmpty);
      expect(s.autoDetectLanguageLabel.trim(), isNotEmpty);
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
