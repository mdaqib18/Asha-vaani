import 'package:flutter/material.dart';

import 'tokens.dart';

/// Compatibility palette aliases backed by V2 [AppTokens.standard].
///
/// New widgets and screens must read `AppTokens.of(context)` directly.
class AppColors {
  AppColors._();

  static const Color canvas = Color(0xFFFAF8F4);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceSubtle = Color(0xFFF3EFE8);
  static const Color border = Color(0xFFE3DED5);

  static const Color primary = Color(0xFF0B5D5E);
  static const Color primaryDark = Color(0xFF074748);
  static const Color primaryTint = Color(0xFFD6EBEA);

  static const Color inkPrimary = Color(0xFF14201F);
  static const Color inkSecondary = Color(0xFF51615F);

  static const Color warningText = Color(0xFF9A5B00);
  static const Color warningBg = Color(0xFFFFF4E0);
  static const Color warningBorder = Color(0xFFC8741A);

  static const Color riskText = Color(0xFFB3261E);
  static const Color riskBg = Color(0xFFFDECEB);
  static const Color riskBorder = Color(0xFFB3261E);

  static const Color successText = Color(0xFF1F7A4D);
  static const Color successBg = Color(0xFFE8F5EE);
}

class AppTheme {
  AppTheme._();

  static ThemeData lightTheme({bool highContrast = false}) {
    final tokens = highContrast ? AppTokens.highContrast : AppTokens.standard;
    final colorScheme = ColorScheme.light(
      primary: tokens.primary,
      onPrimary: Colors.white,
      primaryContainer: tokens.primaryContainer,
      onPrimaryContainer: tokens.ink,
      secondary: tokens.accent,
      onSecondary: Colors.white,
      surface: tokens.surfaceRaised,
      onSurface: tokens.ink,
      onSurfaceVariant: tokens.inkMuted,
      outline: tokens.outline,
      error: tokens.riskHigh,
      onError: Colors.white,
    );

    return ThemeData(
      useMaterial3: true,
      fontFamily: AppTypography.fontFamily,
      fontFamilyFallback: AppTypography.fontFamilyFallback,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: tokens.surface,
      dividerColor: tokens.outline,
      extensions: [tokens],
      appBarTheme: AppBarTheme(
        backgroundColor: tokens.surface,
        foregroundColor: tokens.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: AppTypography.title(tokens.ink),
      ),
      cardTheme: CardThemeData(
        color: tokens.surfaceRaised,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: BorderSide(
            color: tokens.outline,
            width: AppSizes.borderWidth,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: tokens.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(
            AppSizes.minTouchTarget,
            AppSizes.minTouchTarget,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.button),
          ),
          textStyle: AppTypography.bodySemiBold(),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: tokens.primary,
          minimumSize: const Size(
            AppSizes.minTouchTarget,
            AppSizes.minTouchTarget,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          side: BorderSide(
            color: tokens.outline,
            width: AppSizes.borderWidth,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.button),
          ),
          textStyle: AppTypography.bodySemiBold(),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: tokens.primary,
          minimumSize: const Size(
            AppSizes.minTouchTarget,
            AppSizes.minTouchTarget,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          textStyle: AppTypography.label(),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: tokens.surfaceRaised,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.input),
          borderSide: BorderSide(color: tokens.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.input),
          borderSide: BorderSide(color: tokens.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.input),
          borderSide: BorderSide(color: tokens.primary, width: 1.8),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: tokens.surfaceRaised,
        elevation: 0,
        height: 72,
        indicatorColor: tokens.primaryContainer,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return AppTypography.label(selected ? tokens.primary : tokens.inkMuted)
              .copyWith(fontWeight: selected ? FontWeight.w600 : FontWeight.w400);
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? tokens.primary : tokens.inkMuted,
            size: AppSizes.icon,
          );
        }),
      ),
      textTheme: TextTheme(
        displaySmall: AppTypography.display(tokens.ink),
        headlineSmall: AppTypography.title(tokens.ink),
        titleLarge: AppTypography.heading(tokens.ink),
        titleMedium: AppTypography.bodySemiBold(tokens.ink),
        bodyLarge: AppTypography.body(tokens.ink),
        bodyMedium: AppTypography.body(tokens.inkMuted),
        bodySmall: AppTypography.caption(tokens.inkMuted),
        labelLarge: AppTypography.label(tokens.ink),
        labelMedium: AppTypography.label(tokens.inkMuted),
        labelSmall: AppTypography.caption(tokens.inkMuted),
      ),
    );
  }
}
