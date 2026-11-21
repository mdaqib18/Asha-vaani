import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'badges.dart';

enum FieldCardStatus { verified, needsReview, missing, outOfRange }

/// Editable structured-field card displaying value, confidence/status, and edit action.
class FieldCard extends StatelessWidget {
  const FieldCard({
    super.key,
    required this.label,
    required this.valueText,
    required this.status,
    required this.statusLabel,
    this.confidenceLabel,
    this.editLabel,
    this.onEdit,
    this.tabularValue = false,
  });

  final String label;
  final String valueText;
  final FieldCardStatus status;
  final String statusLabel;
  final String? confidenceLabel;
  final String? editLabel;
  final VoidCallback? onEdit;
  final bool tabularValue;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final RiskSeverity severity = switch (status) {
      FieldCardStatus.verified => RiskSeverity.ok,
      FieldCardStatus.needsReview => RiskSeverity.medium,
      FieldCardStatus.missing => RiskSeverity.medium,
      FieldCardStatus.outOfRange => RiskSeverity.high,
    };

    final Color borderColor = switch (status) {
      FieldCardStatus.outOfRange => tokens.riskHigh,
      FieldCardStatus.needsReview => tokens.accent,
      _ => tokens.outline,
    };

    final valueStyle = tabularValue
        ? AppTypography.tabular(AppTypography.heading(tokens.ink))
        : AppTypography.bodySemiBold(tokens.ink);

    return Material(
      color: tokens.surfaceRaised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: BorderSide(color: borderColor, width: AppSizes.borderWidth),
      ),
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(AppRadius.card),
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
                      label,
                      style: AppTypography.labelRegular(tokens.inkMuted),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(valueText, style: valueStyle),
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        RiskBadge(label: statusLabel, severity: severity),
                        if (confidenceLabel != null && confidenceLabel!.isNotEmpty)
                          Text(
                            confidenceLabel!,
                            style: AppTypography.tabular(
                              AppTypography.caption(tokens.inkMuted),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              if (onEdit != null) ...[
                const SizedBox(width: AppSpacing.sm),
                ConstrainedBox(
                  constraints: const BoxConstraints(
                    minWidth: AppSizes.minTouchTarget,
                    minHeight: AppSizes.minTouchTarget,
                  ),
                  child: InkWell(
                    onTap: onEdit,
                    borderRadius: BorderRadius.circular(AppRadius.button),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: AppSpacing.xs,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.edit_outlined,
                            size: 20,
                            color: tokens.primary,
                          ),
                          if (editLabel != null && editLabel!.isNotEmpty) ...[
                            const SizedBox(width: AppSpacing.xs),
                            Text(
                              editLabel!,
                              style: AppTypography.label(tokens.primary),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
