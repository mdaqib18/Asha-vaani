import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'badges.dart';

/// List tile for a beneficiary row with initials avatar, concrete metadata, and risk badge.
class BeneficiaryTile extends StatelessWidget {
  const BeneficiaryTile({
    super.key,
    required this.name,
    required this.typeAndAge,
    this.codeLabel,
    this.dueLabel,
    this.dueOverdue = false,
    this.riskLabel,
    this.riskSeverity,
    this.onTap,
    this.trailingActionLabel,
    this.onTrailingAction,
  });

  final String name;
  final String typeAndAge;
  final String? codeLabel;
  final String? dueLabel;
  final bool dueOverdue;
  final String? riskLabel;
  final RiskSeverity? riskSeverity;
  final VoidCallback? onTap;
  final String? trailingActionLabel;
  final VoidCallback? onTrailingAction;

  String get _initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final dueColor = dueOverdue ? tokens.riskHigh : tokens.inkMuted;

    return Semantics(
      button: onTap != null,
      label: '$name, $typeAndAge${dueLabel != null ? ', $dueLabel' : ''}',
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
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: tokens.primaryContainer,
                    child: Text(
                      _initials,
                      style: AppTypography.label(tokens.primary),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                name,
                                style: AppTypography.bodySemiBold(tokens.ink),
                              ),
                            ),
                            if (codeLabel != null && codeLabel!.isNotEmpty) ...[
                              const SizedBox(width: AppSpacing.sm),
                              Text(
                                codeLabel!,
                                style: AppTypography.tabular(
                                  AppTypography.label(tokens.inkMuted),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          typeAndAge,
                          style: AppTypography.labelRegular(tokens.inkMuted),
                        ),
                        if (dueLabel != null || (riskLabel != null && riskSeverity != null)) ...[
                          const SizedBox(height: AppSpacing.sm),
                          Wrap(
                            spacing: AppSpacing.sm,
                            runSpacing: AppSpacing.xs,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              if (dueLabel != null && dueLabel!.isNotEmpty)
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      dueOverdue
                                          ? Icons.event_busy_rounded
                                          : Icons.event_available_rounded,
                                      size: 16,
                                      color: dueColor,
                                    ),
                                    const SizedBox(width: AppSpacing.xs),
                                    Flexible(
                                      child: Text(
                                        dueLabel!,
                                        style: dueOverdue
                                            ? AppTypography.label(dueColor)
                                            : AppTypography.labelRegular(dueColor),
                                      ),
                                    ),
                                  ],
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
                  if (onTap != null && trailingActionLabel == null) ...[
                    const SizedBox(width: AppSpacing.xs),
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.xs),
                      child: Icon(
                        Icons.chevron_right_rounded,
                        size: AppSizes.icon,
                        color: tokens.inkMuted,
                      ),
                    ),
                  ],
                  if (trailingActionLabel != null && onTrailingAction != null) ...[
                    const SizedBox(width: AppSpacing.sm),
                    TextButton(
                      onPressed: onTrailingAction,
                      style: TextButton.styleFrom(
                        minimumSize: const Size(
                          AppSizes.minTouchTarget,
                          AppSizes.minTouchTarget,
                        ),
                      ),
                      child: Text(
                        trailingActionLabel!,
                        style: AppTypography.label(tokens.primary),
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
