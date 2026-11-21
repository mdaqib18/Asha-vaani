import 'package:flutter/material.dart';

import '../theme/tokens.dart';

enum RiskSeverity { ok, medium, high, info }

/// Clinical or status badge that pairs an icon with descriptive text (never color-only).
class RiskBadge extends StatelessWidget {
  const RiskBadge({
    super.key,
    required this.label,
    required this.severity,
    this.icon,
    this.semanticLabel,
  });

  final String label;
  final RiskSeverity severity;
  final IconData? icon;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final (Color fg, Color bg, IconData defaultIcon) = switch (severity) {
      RiskSeverity.high => (
          tokens.riskHigh,
          tokens.riskHighContainer,
          Icons.warning_amber_rounded,
        ),
      RiskSeverity.medium => (
          tokens.riskMedium,
          tokens.riskMediumContainer,
          Icons.info_outline_rounded,
        ),
      RiskSeverity.ok => (
          tokens.riskOk,
          tokens.riskOkContainer,
          Icons.check_circle_outline_rounded,
        ),
      RiskSeverity.info => (
          tokens.info,
          tokens.infoContainer,
          Icons.info_outline_rounded,
        ),
    };

    return Semantics(
      label: semanticLabel ?? label,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon ?? defaultIcon, size: 16, color: fg),
            const SizedBox(width: AppSpacing.xs),
            Flexible(
              child: Text(
                label,
                style: AppTypography.label(fg),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum SyncChipState { synced, syncing, pending, offline, error }

/// Sync status pill for app header or dashboards. Interactive when [onTap] is provided.
class SyncChip extends StatelessWidget {
  const SyncChip({
    super.key,
    required this.state,
    required this.label,
    this.onTap,
    this.semanticLabel,
  });

  final SyncChipState state;
  final String label;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final (Color fg, Color bg, IconData icon) = switch (state) {
      SyncChipState.synced => (
          tokens.riskOk,
          tokens.riskOkContainer,
          Icons.cloud_done_outlined,
        ),
      SyncChipState.syncing => (
          tokens.info,
          tokens.infoContainer,
          Icons.sync_rounded,
        ),
      SyncChipState.pending => (
          tokens.riskMedium,
          tokens.riskMediumContainer,
          Icons.schedule_rounded,
        ),
      SyncChipState.offline => (
          tokens.inkMuted,
          tokens.surfaceRaised,
          Icons.cloud_off_rounded,
        ),
      SyncChipState.error => (
          tokens.riskHigh,
          tokens.riskHighContainer,
          Icons.sync_problem_rounded,
        ),
    };

    final pill = Container(
      constraints: BoxConstraints(
        minHeight: onTap != null ? AppSizes.minTouchTarget : 32,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(
          color: tokens.outline,
          width: AppSizes.borderWidth,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: AppSpacing.xs),
          Flexible(
            child: Text(
              label,
              style: AppTypography.label(fg),
            ),
          ),
        ],
      ),
    );

    if (onTap == null) {
      return Semantics(label: semanticLabel ?? label, child: pill);
    }

    return Semantics(
      button: true,
      label: semanticLabel ?? label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: pill,
      ),
    );
  }
}

/// Honest security status chip (lock icon + label) opening the Privacy page on tap.
class SecurityChip extends StatelessWidget {
  const SecurityChip({
    super.key,
    required this.label,
    this.onTap,
    this.icon = Icons.lock_outline_rounded,
    this.semanticLabel,
  });

  final String label;
  final VoidCallback? onTap;
  final IconData icon;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final pill = Container(
      constraints: BoxConstraints(
        minHeight: onTap != null ? AppSizes.minTouchTarget : 32,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: tokens.primaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: tokens.primary),
          const SizedBox(width: AppSpacing.xs),
          Flexible(
            child: Text(
              label,
              style: AppTypography.label(tokens.primary),
            ),
          ),
        ],
      ),
    );

    if (onTap == null) {
      return Semantics(label: semanticLabel ?? label, child: pill);
    }

    return Semantics(
      button: true,
      label: semanticLabel ?? label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: pill,
      ),
    );
  }
}
