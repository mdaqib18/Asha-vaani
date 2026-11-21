import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../ui/ui.dart';

/// Plain-language Privacy & Data page showing only genuinely active security mechanisms (`SPEC_V2 §7`).
class PrivacyAndDataScreen extends StatefulWidget {
  const PrivacyAndDataScreen({super.key, required this.appState});

  final AppState appState;

  @override
  State<PrivacyAndDataScreen> createState() => _PrivacyAndDataScreenState();
}

class _PrivacyAndDataScreenState extends State<PrivacyAndDataScreen> {
  bool _runningCleanup = false;
  int? _lastCleanedCount;

  Future<void> _runCleanup() async {
    if (_runningCleanup) return;
    setState(() => _runningCleanup = true);
    try {
      final count = await widget.appState.runAudioRetentionSweep();
      if (!mounted) return;
      setState(() => _lastCleanedCount = count);
    } finally {
      if (mounted) {
        setState(() => _runningCleanup = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.appState,
      builder: (context, _) {
        final tokens = AppTokens.of(context);
        final strings = widget.appState.strings;
        final s = widget.appState;

        final checks = <({String label, String status, RiskSeverity severity})>[
          (
            label: strings.encryptionStatusLabel,
            status: s.isLocalDbEncrypted
                ? strings.statusActiveLabel
                : strings.statusInactiveLabel,
            severity:
                s.isLocalDbEncrypted ? RiskSeverity.ok : RiskSeverity.medium,
          ),
          (
            label: strings.appLockStatusLabel,
            status: s.hasOfflineCredentials
                ? strings.statusActiveLabel
                : strings.statusInactiveLabel,
            severity: s.hasOfflineCredentials
                ? RiskSeverity.ok
                : RiskSeverity.info,
          ),
          (
            label: strings.autoLockStatusLabel,
            status: strings.autoLockOptionSeconds(s.autoLockSeconds),
            severity: RiskSeverity.ok,
          ),
          (
            label: strings.biometricStatusLabel,
            status: (s.biometricAvailable && s.biometricEnabled)
                ? strings.statusActiveLabel
                : strings.statusInactiveLabel,
            severity: (s.biometricAvailable && s.biometricEnabled)
                ? RiskSeverity.ok
                : RiskSeverity.info,
          ),
          (
            label: strings.screenProtectionStatusLabel,
            status: s.isScreenProtected
                ? strings.statusActiveLabel
                : strings.statusInactiveLabel,
            severity:
                s.isScreenProtected ? RiskSeverity.ok : RiskSeverity.medium,
          ),
          (
            label: strings.transportSecurityLabel,
            status: s.isHttpsTransport
                ? strings.httpsEncryptedLabel
                : strings.httpUnencryptedLabel,
            severity:
                s.isHttpsTransport ? RiskSeverity.ok : RiskSeverity.medium,
          ),
        ];

        final sections = <({String title, String body, IconData icon})>[
          (
            title: strings.privacyCollectedTitle,
            body: strings.privacyCollectedBody,
            icon: Icons.assignment_outlined,
          ),
          (
            title: strings.privacyStorageTitle,
            body: strings.privacyStorageBody,
            icon: Icons.enhanced_encryption_outlined,
          ),
          (
            title: strings.privacyRetentionTitle,
            body: strings.privacyRetentionBody,
            icon: Icons.auto_delete_outlined,
          ),
          (
            title: strings.privacyAccessTitle,
            body: strings.privacyAccessBody,
            icon: Icons.visibility_off_outlined,
          ),
          (
            title: strings.privacyDeletionTitle,
            body: strings.privacyDeletionBody,
            icon: Icons.history_edu_outlined,
          ),
        ];

        return AppScaffold(
          title: strings.privacyAndDataTitle,
          body: ListView(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
            children: [
              SectionHeader(title: strings.securityStatusTitle),
              const SizedBox(height: AppSpacing.sm),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  color: tokens.surfaceRaised,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  border: Border.all(
                    color: tokens.outline,
                    width: AppSizes.borderWidth,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < checks.length; i++) ...[
                      if (i > 0) Divider(color: tokens.outline, height: 20),
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.xs,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            checks[i].label,
                            style: AppTypography.body(tokens.ink),
                          ),
                          RiskBadge(
                            label: checks[i].status,
                            severity: checks[i].severity,
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              for (final section in sections) ...[
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: AppSpacing.md),
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  decoration: BoxDecoration(
                    color: tokens.surfaceRaised,
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    border: Border.all(
                      color: tokens.outline,
                      width: AppSizes.borderWidth,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            section.icon,
                            size: AppSizes.icon,
                            color: tokens.primary,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(
                              section.title,
                              style: AppTypography.heading(tokens.ink),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        section.body,
                        style: AppTypography.body(tokens.inkMuted),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.sm),
              SecondaryButton(
                label: strings.runAudioCleanupAction,
                icon: Icons.cleaning_services_outlined,
                onPressed: _runningCleanup ? null : _runCleanup,
              ),
              if (_lastCleanedCount != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  strings.audioCleanupResult(_lastCleanedCount!),
                  style: AppTypography.labelRegular(tokens.riskOk),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
