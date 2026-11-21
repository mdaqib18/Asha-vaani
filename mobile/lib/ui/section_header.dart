import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'buttons.dart';

/// Left-aligned section heading with optional inline trailing action.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTypography.heading(tokens.ink)),
              if (subtitle != null && subtitle!.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(subtitle!, style: AppTypography.labelRegular(tokens.inkMuted)),
              ],
            ],
          ),
        ),
        if (actionLabel != null && onAction != null)
          TextAction(label: actionLabel!, onPressed: onAction),
      ],
    );
  }
}
