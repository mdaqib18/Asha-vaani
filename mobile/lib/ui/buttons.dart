import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Full-width or intrinsic high-contrast primary action with mandatory icon + text.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.loading = false,
    this.expand = true,
    this.destructive = false,
    this.semanticLabel,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool loading;
  final bool expand;
  final bool destructive;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final bg = destructive ? tokens.riskHigh : tokens.primary;
    final effectiveOnPressed = (loading || onPressed == null) ? null : onPressed;

    final button = FilledButton(
      onPressed: effectiveOnPressed,
      style: FilledButton.styleFrom(
        backgroundColor: bg,
        foregroundColor: Colors.white,
        disabledBackgroundColor: tokens.outline,
        disabledForegroundColor: tokens.inkMuted,
        elevation: 0,
        minimumSize: Size(
          expand ? double.infinity : AppSizes.minTouchTarget,
          AppSizes.minTouchTarget,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
        ),
      ),
      child: _ButtonContent(
        label: label,
        icon: icon,
        loading: loading,
        foreground: effectiveOnPressed == null ? tokens.inkMuted : Colors.white,
      ),
    );

    return Semantics(
      button: true,
      enabled: effectiveOnPressed != null,
      label: semanticLabel ?? label,
      child: button,
    );
  }
}

/// Secondary outlined button with hairline border and >= 48dp touch height.
class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.loading = false,
    this.expand = true,
    this.semanticLabel,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool loading;
  final bool expand;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final effectiveOnPressed = (loading || onPressed == null) ? null : onPressed;

    final button = OutlinedButton(
      onPressed: effectiveOnPressed,
      style: OutlinedButton.styleFrom(
        backgroundColor: tokens.surfaceRaised,
        foregroundColor: tokens.primary,
        disabledForegroundColor: tokens.inkMuted,
        elevation: 0,
        minimumSize: Size(
          expand ? double.infinity : AppSizes.minTouchTarget,
          AppSizes.minTouchTarget,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        side: BorderSide(
          color: effectiveOnPressed == null ? tokens.outline : tokens.primary,
          width: AppSizes.borderWidth,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
        ),
      ),
      child: _ButtonContent(
        label: label,
        icon: icon,
        loading: loading,
        foreground: effectiveOnPressed == null ? tokens.inkMuted : tokens.primary,
      ),
    );

    return Semantics(
      button: true,
      enabled: effectiveOnPressed != null,
      label: semanticLabel ?? label,
      child: button,
    );
  }
}

/// Inline text action preserving >= 48dp minimum touch target.
class TextAction extends StatelessWidget {
  const TextAction({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.destructive = false,
    this.semanticLabel,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool destructive;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final fg = onPressed == null
        ? tokens.inkMuted
        : (destructive ? tokens.riskHigh : tokens.primary);

    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: semanticLabel ?? label,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: fg,
          minimumSize: const Size(
            AppSizes.minTouchTarget,
            AppSizes.minTouchTarget,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.sm,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: fg),
              const SizedBox(width: AppSpacing.xs),
            ],
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

class _ButtonContent extends StatelessWidget {
  const _ButtonContent({
    required this.label,
    required this.icon,
    required this.loading,
    required this.foreground,
  });

  final String label;
  final IconData icon;
  final bool loading;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (loading)
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(foreground),
            ),
          )
        else
          Icon(icon, size: 22, color: foreground),
        const SizedBox(width: AppSpacing.sm),
        Flexible(
          child: Text(
            label,
            style: AppTypography.bodySemiBold(foreground),
          ),
        ),
      ],
    );
  }
}
