import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'buttons.dart';

/// Confirmation bottom sheet with left-aligned copy and >= 48dp explicit confirm/cancel actions.
class ConfirmSheet extends StatelessWidget {
  const ConfirmSheet({
    super.key,
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.onConfirm,
    required this.onCancel,
    this.confirmIcon = Icons.check_rounded,
    this.destructive = false,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final String cancelLabel;
  final IconData confirmIcon;
  final bool destructive;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  static Future<bool> show(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmLabel,
    required String cancelLabel,
    IconData confirmIcon = Icons.check_rounded,
    bool destructive = false,
  }) async {
    final tokens = AppTokens.of(context);
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: tokens.surfaceRaised,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => ConfirmSheet(
        title: title,
        message: message,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
        confirmIcon: confirmIcon,
        destructive: destructive,
        onConfirm: () => Navigator.of(sheetContext).pop(true),
        onCancel: () => Navigator.of(sheetContext).pop(false),
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.xl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: AppTypography.title(tokens.ink)),
              const SizedBox(height: AppSpacing.sm),
              Text(message, style: AppTypography.body(tokens.inkMuted)),
              const SizedBox(height: AppSpacing.xl),
              PrimaryButton(
                label: confirmLabel,
                icon: confirmIcon,
                destructive: destructive,
                onPressed: onConfirm,
              ),
              const SizedBox(height: AppSpacing.sm),
              SecondaryButton(
                label: cancelLabel,
                icon: Icons.close_rounded,
                onPressed: onCancel,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
