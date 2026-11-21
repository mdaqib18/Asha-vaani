import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'badges.dart';

/// List tile for a recorded visit showing purpose, timestamp/meta, status, and risk badge.
class VisitTile extends StatelessWidget {
  const VisitTile({
    super.key,
    required this.purposeLabel,
    required this.subtitle,
    this.statusLabel,
    this.statusSeverity,
    this.riskLabel,
    this.riskSeverity,
    this.onTap,
  });

  final String purposeLabel;
  final String subtitle;
  final String? statusLabel;
  final RiskSeverity? statusSeverity;
  final String? riskLabel;
  final RiskSeverity? riskSeverity;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);

    return Semantics(
      button: onTap != null,
      label: '$purposeLabel, $subtitle',
      child: Material(
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
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          purposeLabel,
                          style: AppTypography.bodySemiBold(tokens.ink),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          subtitle,
                          style: AppTypography.tabular(
                            AppTypography.labelRegular(tokens.inkMuted),
                          ),
                        ),
                        if ((statusLabel != null && statusSeverity != null) ||
                            (riskLabel != null && riskSeverity != null)) ...[
                          const SizedBox(height: AppSpacing.sm),
                          Wrap(
                            spacing: AppSpacing.sm,
                            runSpacing: AppSpacing.xs,
                            children: [
                              if (statusLabel != null && statusSeverity != null)
                                RiskBadge(
                                  label: statusLabel!,
                                  severity: statusSeverity!,
                                ),
                              if (riskLabel != null && riskSeverity != null)
                                RiskBadge(
                                  label: riskLabel!,
                                  severity: riskSeverity!,
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (onTap != null) ...[
                    const SizedBox(width: AppSpacing.sm),
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.xs),
                      child: Icon(
                        Icons.chevron_right_rounded,
                        size: AppSizes.icon,
                        color: tokens.inkMuted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
