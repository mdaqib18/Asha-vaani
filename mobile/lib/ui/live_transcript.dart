import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Live streaming caption surface showing finalized text, muted partial text,
/// highlighted numeric tokens/IDs, optional level bar, and offline pause state.
class LiveTranscript extends StatelessWidget {
  const LiveTranscript({
    super.key,
    required this.finalizedText,
    this.partialText = '',
    this.placeholder = '',
    this.pausedNotice,
    this.audioLevel,
    this.label,
  });

  final String finalizedText;
  final String partialText;
  final String placeholder;
  final String? pausedNotice;
  final double? audioLevel;
  final String? label;

  static final RegExp _numberPattern = RegExp(r'\d+(?:\.\d+)?');

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final trimmedFinal = finalizedText.trim();
    final trimmedPartial = partialText.trim();
    final isEmpty = trimmedFinal.isEmpty && trimmedPartial.isEmpty;

    return Semantics(
      liveRegion: true,
      label: label ?? (isEmpty ? placeholder : '$trimmedFinal $trimmedPartial'.trim()),
      child: Container(
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
          mainAxisSize: MainAxisSize.min,
          children: [
            if (label != null && label!.isNotEmpty) ...[
              Text(
                label!,
                style: AppTypography.label(tokens.inkMuted),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            if (audioLevel != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.pill),
                child: LinearProgressIndicator(
                  value: audioLevel!.clamp(0.0, 1.0),
                  minHeight: 4,
                  backgroundColor: tokens.outline,
                  valueColor: AlwaysStoppedAnimation<Color>(tokens.primary),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            if (pausedNotice != null && pausedNotice!.isNotEmpty) ...[
              Row(
                children: [
                  Icon(
                    Icons.wifi_off_rounded,
                    size: 16,
                    color: tokens.riskMedium,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      pausedNotice!,
                      style: AppTypography.label(tokens.riskMedium),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            if (isEmpty)
              Text(
                placeholder,
                style: AppTypography.body(tokens.inkMuted),
              )
            else
              Text.rich(
                TextSpan(
                  children: [
                    ..._buildHighlightedSpans(trimmedFinal, tokens),
                    if (trimmedFinal.isNotEmpty && trimmedPartial.isNotEmpty)
                      const TextSpan(text: ' '),
                    if (trimmedPartial.isNotEmpty)
                      TextSpan(
                        text: trimmedPartial,
                        style: AppTypography.body(tokens.inkMuted),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<InlineSpan> _buildHighlightedSpans(String text, AppTokens tokens) {
    if (text.isEmpty) return const [];
    final spans = <InlineSpan>[];
    var cursor = 0;

    for (final match in _numberPattern.allMatches(text)) {
      if (match.start > cursor) {
        spans.add(
          TextSpan(
            text: text.substring(cursor, match.start),
            style: AppTypography.body(tokens.ink),
          ),
        );
      }
      spans.add(
        TextSpan(
          text: match.group(0),
          style: AppTypography.tabular(AppTypography.bodySemiBold(tokens.primary))
              .copyWith(backgroundColor: tokens.primaryContainer),
        ),
      );
      cursor = match.end;
    }

    if (cursor < text.length) {
      spans.add(
        TextSpan(
          text: text.substring(cursor),
          style: AppTypography.body(tokens.ink),
        ),
      );
    }
    return spans;
  }
}
