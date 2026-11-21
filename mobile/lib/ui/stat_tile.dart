import 'package:flutter/material.dart';

import '../theme/tokens.dart';

enum StatTileTone { neutral, attention, ok }

/// Summary metric tile with tabular figures, 1px outline border, and optional tap drill-down.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.value,
    required this.label,
    this.icon,
    this.tone = StatTileTone.neutral,
    this.onTap,
    this.semanticLabel,
  });

  final String value;
  final String label;
  final IconData? icon;
  final StatTileTone tone;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final (Color valueColor, Color bg) = switch (tone) {
      StatTileTone.neutral => (tokens.ink, tokens.surfaceRaised),
      StatTileTone.attention => (tokens.riskHigh, tokens.riskHighContainer),
      StatTileTone.ok => (tokens.riskOk, tokens.riskOkContainer),
    };

    final content = Container(
      constraints: const BoxConstraints(minHeight: AppSizes.minTouchTarget),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: tokens.outline,
          width: AppSizes.borderWidth,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  value,
                  style: AppTypography.tabular(AppTypography.title(valueColor)),
                ),
              ),
              if (icon != null) Icon(icon, size: 20, color: valueColor),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            label,
            style: AppTypography.labelRegular(tokens.inkMuted),
          ),
        ],
      ),
    );

    if (onTap == null) {
      return Semantics(label: semanticLabel ?? '$label: $value', child: content);
    }

    return Semantics(
      button: true,
      label: semanticLabel ?? '$label: $value',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: content,
      ),
    );
  }
}
