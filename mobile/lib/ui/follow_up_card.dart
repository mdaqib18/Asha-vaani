import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'buttons.dart';

/// Spoken/visual follow-up prompt card for missing required fields or ambiguities.
class FollowUpCard extends StatelessWidget {
  const FollowUpCard({
    super.key,
    required this.stepLabel,
    required this.questionText,
    this.replayLabel,
    this.onReplay,
    this.skipLabel,
    this.onSkip,
  });

  final String stepLabel;
  final String questionText;
  final String? replayLabel;
  final VoidCallback? onReplay;
  final String? skipLabel;
  final VoidCallback? onSkip;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);

    return Semantics(
      liveRegion: true,
      label: '$stepLabel: $questionText',
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: tokens.surfaceRaised,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(
            color: tokens.outline,
            width: AppSizes.borderWidth,
          ),
        ),
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.record_voice_over_outlined,
                  size: 18,
                  color: tokens.primary,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    stepLabel,
                    style: AppTypography.tabular(
                      AppTypography.label(tokens.primary),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              questionText,
              style: AppTypography.bodySemiBold(tokens.ink),
            ),
            if ((replayLabel != null && onReplay != null) ||
                (skipLabel != null && onSkip != null)) ...[
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.xs,
                children: [
                  if (replayLabel != null && onReplay != null)
                    TextAction(
                      label: replayLabel!,
                      icon: Icons.volume_up_outlined,
                      onPressed: onReplay,
                    ),
                  if (skipLabel != null && onSkip != null)
                    TextAction(
                      label: skipLabel!,
                      icon: Icons.edit_note_rounded,
                      onPressed: onSkip,
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
