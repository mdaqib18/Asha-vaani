import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../ui/ui.dart';
import '../widgets/language_toggle.dart';
import '../widgets/server_settings_sheet.dart';
import 'privacy_and_data_screen.dart';
import 'saved_visits_screen.dart';
import 'supervisor_flagged_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.appState,
    required this.refreshSignal,
  });

  final AppState appState;
  final ValueNotifier<int> refreshSignal;

  void _openPrivacyScreen(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PrivacyAndDataScreen(appState: appState),
      ),
    );
  }

  void _showAutoLockSheet(BuildContext context) {
    final tokens = AppTokens.of(context);
    final strings = appState.strings;
    const options = [30, 60, 300];
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: tokens.surfaceRaised,
      builder: (sheetContext) {
        return Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                strings.autoLockLabel,
                style: AppTypography.heading(tokens.ink),
              ),
              const SizedBox(height: AppSpacing.sm),
              for (final secs in options)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    strings.autoLockOptionSeconds(secs),
                    style: AppTypography.bodySemiBold(tokens.ink),
                  ),
                  trailing: appState.autoLockSeconds == secs
                      ? Icon(Icons.check_rounded, color: tokens.primary)
                      : null,
                  onTap: () async {
                    await appState.setAutoLockSeconds(secs);
                    if (sheetContext.mounted) {
                      Navigator.of(sheetContext).pop();
                    }
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmSignOut(BuildContext context) async {
    final strings = appState.strings;
    final confirmed = await ConfirmSheet.show(
      context,
      title: strings.signOutConfirmTitle,
      message: strings.signOutConfirmMessage,
      confirmLabel: strings.signOutAction,
      cancelLabel: strings.cancel,
      confirmIcon: Icons.logout_rounded,
      destructive: true,
    );
    if (confirmed) {
      await appState.signOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final strings = appState.strings;
    final profile = appState.selectedProfile;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        0,
        AppSpacing.lg,
        0,
        AppSpacing.xxl,
      ),
      children: [
        if (profile != null) ...[
          Container(
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
                Text(
                  strings.signedInAs(profile.name, profile.id),
                  style: AppTypography.bodySemiBold(tokens.ink),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  profile.area,
                  style: AppTypography.labelRegular(tokens.inkMuted),
                ),
                const SizedBox(height: AppSpacing.md),
                SecurityChip(
                  label: appState.isLocalDbEncrypted
                      ? strings.encryptedOnDeviceChip
                      : (appState.hasOfflineCredentials
                          ? strings.pinLockOfflineChip
                          : strings.pinLockChip),
                  onTap: () => _openPrivacyScreen(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
        SectionHeader(title: strings.languageSectionLabel),
        const SizedBox(height: AppSpacing.sm),
        Align(
          alignment: Alignment.centerLeft,
          child: LanguageToggle(
            selected: appState.language,
            onChanged: appState.setLanguage,
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        Container(
          decoration: BoxDecoration(
            color: tokens.surfaceRaised,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(
              color: tokens.outline,
              width: AppSizes.borderWidth,
            ),
          ),
          child: SwitchListTile(
            value: appState.highContrast,
            onChanged: appState.setHighContrast,
            activeThumbColor: tokens.primary,
            title: Text(
              strings.highContrastLabel,
              style: AppTypography.bodySemiBold(tokens.ink),
            ),
            subtitle: Text(
              strings.highContrastSubtitle,
              style: AppTypography.labelRegular(tokens.inkMuted),
            ),
          ),
        ),
        if (appState.biometricAvailable) ...[
          const SizedBox(height: AppSpacing.sm),
          Container(
            decoration: BoxDecoration(
              color: tokens.surfaceRaised,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(
                color: tokens.outline,
                width: AppSizes.borderWidth,
              ),
            ),
            child: SwitchListTile(
              value: appState.biometricEnabled,
              onChanged: appState.setBiometricEnabled,
              activeThumbColor: tokens.primary,
              title: Text(
                strings.biometricUnlockLabel,
                style: AppTypography.bodySemiBold(tokens.ink),
              ),
            ),
          ),
        ],
        if (appState.allowDevSecurityToggle) ...[
          const SizedBox(height: AppSpacing.sm),
          Container(
            decoration: BoxDecoration(
              color: tokens.surfaceRaised,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(
                color: tokens.outline,
                width: AppSizes.borderWidth,
              ),
            ),
            child: SwitchListTile(
              key: const ValueKey('dev_screenshot_protection_toggle'),
              value: !appState.screenshotProtectionEnabled,
              onChanged: (disable) =>
                  appState.setScreenshotProtectionEnabled(!disable),
              activeThumbColor: tokens.accent,
              title: Text(
                strings.screenshotProtectionDevLabel,
                style: AppTypography.bodySemiBold(tokens.ink),
              ),
              subtitle: Text(
                strings.screenshotProtectionDevSubtitle,
                style: AppTypography.labelRegular(tokens.inkMuted),
              ),
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        _SettingsRow(
          icon: Icons.lock_clock_outlined,
          label: strings.autoLockLabel,
          subtitle: strings.autoLockOptionSeconds(appState.autoLockSeconds),
          onTap: () => _showAutoLockSheet(context),
        ),
        const SizedBox(height: AppSpacing.md),
        _SettingsRow(
          icon: Icons.fact_check_outlined,
          label: strings.syncAndQueueLabel,
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => AppScaffold(
                  title: strings.savedVisitsTab,
                  body: SavedVisitsScreen(
                    appState: appState,
                    refreshSignal: refreshSignal,
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: AppSpacing.sm),
        _SettingsRow(
          icon: Icons.health_and_safety_outlined,
          label: strings.supervisorTitle,
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => SupervisorFlaggedScreen(appState: appState),
              ),
            );
          },
        ),
        const SizedBox(height: AppSpacing.sm),
        _SettingsRow(
          icon: Icons.tune_rounded,
          label: strings.serverSettings,
          subtitle: appState.baseUrl,
          onTap: () => showServerSettingsSheet(context, appState),
        ),
        const SizedBox(height: AppSpacing.sm),
        _SettingsRow(
          icon: Icons.timer_outlined,
          label: strings.paperBaselineLabel,
          subtitle: appState.paperBaselineMinutes != null
              ? '${appState.paperBaselineMinutes!.toStringAsFixed(1)} min'
              : strings.paperBaselineUnset,
          onTap: () => showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            backgroundColor: tokens.surfaceRaised,
            builder: (_) => _PaperBaselineSheet(appState: appState),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        _SettingsRow(
          icon: Icons.privacy_tip_outlined,
          label: strings.privacyAndDataTitle,
          onTap: () => _openPrivacyScreen(context),
        ),
        const SizedBox(height: AppSpacing.sm),
        _SettingsRow(
          icon: Icons.palette_outlined,
          label: strings.openUiGalleryLabel,
          onTap: () => Navigator.of(context).pushNamed('/gallery'),
        ),
        const SizedBox(height: AppSpacing.xl),
        SecondaryButton(
          label: strings.lockAppAction,
          icon: Icons.lock_outline_rounded,
          onPressed: appState.lockApp,
        ),
        const SizedBox(height: AppSpacing.sm),
        Align(
          alignment: Alignment.centerLeft,
          child: TextAction(
            label: strings.signOutAction,
            icon: Icons.logout_rounded,
            destructive: true,
            onPressed: () => _confirmSignOut(context),
          ),
        ),
      ],
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Material(
      color: tokens.surfaceRaised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: BorderSide(
          color: tokens.outline,
          width: AppSizes.borderWidth,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppSizes.minTouchTarget),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            child: Row(
              children: [
                Icon(icon, size: AppSizes.icon, color: tokens.primary),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: AppTypography.bodySemiBold(tokens.ink)),
                      if (subtitle != null && subtitle!.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          subtitle!,
                          style: AppTypography.labelRegular(tokens.inkMuted),
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: AppSizes.icon,
                  color: tokens.inkMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PaperBaselineSheet extends StatefulWidget {
  const _PaperBaselineSheet({required this.appState});

  final AppState appState;

  @override
  State<_PaperBaselineSheet> createState() => _PaperBaselineSheetState();
}

class _PaperBaselineSheetState extends State<_PaperBaselineSheet> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    final existing = widget.appState.paperBaselineMinutes;
    _controller = TextEditingController(
      text: existing != null ? existing.toStringAsFixed(1) : '',
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final parsed = double.tryParse(_controller.text.trim());
    await widget.appState.setPaperBaselineMinutes(
      parsed != null && parsed > 0 ? parsed : null,
    );
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _clear() async {
    await widget.appState.setPaperBaselineMinutes(null);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.appState.strings;
    final tokens = AppTokens.of(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xl,
        AppSpacing.lg,
        AppSpacing.xl + bottomInset,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            strings.paperBaselineLabel,
            style: AppTypography.heading(tokens.ink),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            strings.paperBaselineSubtitle,
            style: AppTypography.labelRegular(tokens.inkMuted),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              hintText: strings.paperBaselineHint,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          PrimaryButton(
            label: strings.save,
            icon: Icons.check_rounded,
            onPressed: _save,
          ),
          const SizedBox(height: AppSpacing.sm),
          SecondaryButton(
            label: strings.clearBaselineAction,
            icon: Icons.clear_rounded,
            onPressed: _clear,
          ),
        ],
      ),
    );
  }
}
