import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'buttons.dart';

/// Calm empty-list or no-work-due state with concrete guidance and optional action.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.actionIcon,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final IconData? actionIcon;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xl),
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
          Icon(icon, size: 32, color: tokens.primary),
          const SizedBox(height: AppSpacing.md),
          Text(title, style: AppTypography.heading(tokens.ink)),
          if (message != null && message!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(message!, style: AppTypography.body(tokens.inkMuted)),
          ],
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: AppSpacing.lg),
            PrimaryButton(
              label: actionLabel!,
              icon: actionIcon ?? Icons.add_rounded,
              onPressed: onAction,
            ),
          ],
        ],
      ),
    );
  }
}

/// Designed failure state with plain explanation and explicit retry button.
class ErrorState extends StatelessWidget {
  const ErrorState({
    super.key,
    required this.title,
    required this.message,
    this.retryLabel,
    this.onRetry,
    this.icon = Icons.error_outline_rounded,
  });

  final String title;
  final String message;
  final String? retryLabel;
  final VoidCallback? onRetry;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: tokens.riskHighContainer,
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
          Icon(icon, size: 28, color: tokens.riskHigh),
          const SizedBox(height: AppSpacing.sm),
          Text(title, style: AppTypography.heading(tokens.riskHigh)),
          const SizedBox(height: AppSpacing.xs),
          Text(message, style: AppTypography.body(tokens.ink)),
          if (retryLabel != null && onRetry != null) ...[
            const SizedBox(height: AppSpacing.lg),
            SecondaryButton(
              label: retryLabel!,
              icon: Icons.refresh_rounded,
              onPressed: onRetry,
            ),
          ],
        ],
      ),
    );
  }
}

/// Calm placeholder loading skeleton respecting system reduce-motion preferences.
class SkeletonLoader extends StatefulWidget {
  const SkeletonLoader({
    super.key,
    this.itemCount = 3,
    this.itemHeight = 72,
  });

  final int itemCount;
  final double itemHeight;

  @override
  State<SkeletonLoader> createState() => _SkeletonLoaderState();
}

class _SkeletonLoaderState extends State<SkeletonLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduceMotion) {
      if (_controller.isAnimating) _controller.stop();
      _controller.value = 0.5;
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final barColor = Color.lerp(
          tokens.outline,
          tokens.primaryContainer,
          0.25 * _controller.value,
        )!;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(widget.itemCount, (index) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: index + 1 < widget.itemCount ? AppSpacing.md : 0,
              ),
              child: Container(
                height: widget.itemHeight,
                padding: const EdgeInsets.all(AppSpacing.md),
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
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      height: 14,
                      width: 160,
                      decoration: BoxDecoration(
                        color: barColor,
                        borderRadius: BorderRadius.circular(AppRadius.subtle),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Container(
                      height: 12,
                      width: 110,
                      decoration: BoxDecoration(
                        color: barColor,
                        borderRadius: BorderRadius.circular(AppRadius.subtle),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
