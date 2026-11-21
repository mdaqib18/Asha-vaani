import 'package:flutter/material.dart';

/// Design tokens for Asha Vaani V2 ("calm clinical, warm", SPEC_V2.md §2).
@immutable
class AppTokens extends ThemeExtension<AppTokens> {
  const AppTokens({
    required this.primary,
    required this.primaryContainer,
    required this.ink,
    required this.inkMuted,
    required this.surface,
    required this.surfaceRaised,
    required this.outline,
    required this.accent,
    required this.riskHigh,
    required this.riskHighContainer,
    required this.riskMedium,
    required this.riskMediumContainer,
    required this.riskOk,
    required this.riskOkContainer,
    required this.info,
    required this.infoContainer,
    this.isHighContrast = false,
  });

  final Color primary;
  final Color primaryContainer;
  final Color ink;
  final Color inkMuted;
  final Color surface;
  final Color surfaceRaised;
  final Color outline;
  final Color accent;
  final Color riskHigh;
  final Color riskHighContainer;
  final Color riskMedium;
  final Color riskMediumContainer;
  final Color riskOk;
  final Color riskOkContainer;
  final Color info;
  final Color infoContainer;
  final bool isHighContrast;

  static const AppTokens standard = AppTokens(
    primary: Color(0xFF0B5D5E),
    primaryContainer: Color(0xFFD6EBEA),
    ink: Color(0xFF14201F),
    inkMuted: Color(0xFF51615F),
    surface: Color(0xFFFAF8F4),
    surfaceRaised: Color(0xFFFFFFFF),
    outline: Color(0xFFE3DED5),
    accent: Color(0xFFC8741A),
    riskHigh: Color(0xFFB3261E),
    riskHighContainer: Color(0xFFFDECEB),
    riskMedium: Color(0xFF9A5B00),
    riskMediumContainer: Color(0xFFFFF4E0),
    riskOk: Color(0xFF1F7A4D),
    riskOkContainer: Color(0xFFE8F5EE),
    info: Color(0xFF1D5E8C),
    infoContainer: Color(0xFFE8F2F9),
    isHighContrast: false,
  );

  /// Outdoor-sunlight high-contrast variant preserving the calm clinical identity.
  static const AppTokens highContrast = AppTokens(
    primary: Color(0xFF074748),
    primaryContainer: Color(0xFFC7E3E2),
    ink: Color(0xFF0B1211),
    inkMuted: Color(0xFF2F3D3B),
    surface: Color(0xFFFFFFFF),
    surfaceRaised: Color(0xFFFFFFFF),
    outline: Color(0xFF7B8582),
    accent: Color(0xFF9A550A),
    riskHigh: Color(0xFF8E1812),
    riskHighContainer: Color(0xFFFCE4E2),
    riskMedium: Color(0xFF7A4700),
    riskMediumContainer: Color(0xFFFFECCC),
    riskOk: Color(0xFF155E39),
    riskOkContainer: Color(0xFFDCF0E5),
    info: Color(0xFF14486E),
    infoContainer: Color(0xFFDDEBF6),
    isHighContrast: true,
  );

  static AppTokens of(BuildContext context) {
    return Theme.of(context).extension<AppTokens>() ?? standard;
  }

  @override
  AppTokens copyWith({
    Color? primary,
    Color? primaryContainer,
    Color? ink,
    Color? inkMuted,
    Color? surface,
    Color? surfaceRaised,
    Color? outline,
    Color? accent,
    Color? riskHigh,
    Color? riskHighContainer,
    Color? riskMedium,
    Color? riskMediumContainer,
    Color? riskOk,
    Color? riskOkContainer,
    Color? info,
    Color? infoContainer,
    bool? isHighContrast,
  }) {
    return AppTokens(
      primary: primary ?? this.primary,
      primaryContainer: primaryContainer ?? this.primaryContainer,
      ink: ink ?? this.ink,
      inkMuted: inkMuted ?? this.inkMuted,
      surface: surface ?? this.surface,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      outline: outline ?? this.outline,
      accent: accent ?? this.accent,
      riskHigh: riskHigh ?? this.riskHigh,
      riskHighContainer: riskHighContainer ?? this.riskHighContainer,
      riskMedium: riskMedium ?? this.riskMedium,
      riskMediumContainer: riskMediumContainer ?? this.riskMediumContainer,
      riskOk: riskOk ?? this.riskOk,
      riskOkContainer: riskOkContainer ?? this.riskOkContainer,
      info: info ?? this.info,
      infoContainer: infoContainer ?? this.infoContainer,
      isHighContrast: isHighContrast ?? this.isHighContrast,
    );
  }

  @override
  AppTokens lerp(ThemeExtension<AppTokens>? other, double t) {
    if (other is! AppTokens) return this;
    return AppTokens(
      primary: Color.lerp(primary, other.primary, t)!,
      primaryContainer:
          Color.lerp(primaryContainer, other.primaryContainer, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      inkMuted: Color.lerp(inkMuted, other.inkMuted, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceRaised: Color.lerp(surfaceRaised, other.surfaceRaised, t)!,
      outline: Color.lerp(outline, other.outline, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      riskHigh: Color.lerp(riskHigh, other.riskHigh, t)!,
      riskHighContainer:
          Color.lerp(riskHighContainer, other.riskHighContainer, t)!,
      riskMedium: Color.lerp(riskMedium, other.riskMedium, t)!,
      riskMediumContainer:
          Color.lerp(riskMediumContainer, other.riskMediumContainer, t)!,
      riskOk: Color.lerp(riskOk, other.riskOk, t)!,
      riskOkContainer: Color.lerp(riskOkContainer, other.riskOkContainer, t)!,
      info: Color.lerp(info, other.info, t)!,
      infoContainer: Color.lerp(infoContainer, other.infoContainer, t)!,
      isHighContrast: t < 0.5 ? isHighContrast : other.isHighContrast,
    );
  }
}

class AppSpacing {
  AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;

  static const double screenHorizontal = 16;
  static const double sectionGap = 24;
}

class AppRadius {
  AppRadius._();

  static const double subtle = 6;
  static const double card = 12;
  static const double input = 12;
  static const double button = 14;
  static const double pill = 999;
}

class AppSizes {
  AppSizes._();

  static const double minTouchTarget = 48;
  static const double micButton = 88;
  static const double icon = 24;
  static const double borderWidth = 1;
}

class AppMotion {
  AppMotion._();

  static const Duration fast = Duration(milliseconds: 150);
  static const Duration standard = Duration(milliseconds: 220);
  static const Curve curve = Curves.easeOut;
}

class AppTypography {
  AppTypography._();

  static const String fontFamily = 'NotoSans';
  static const List<String> fontFamilyFallback = [
    'NotoSansDevanagari',
    'NotoSansKannada',
  ];

  static TextStyle base({
    required double size,
    FontWeight weight = FontWeight.w400,
    double height = 1.4,
    Color? color,
    bool tabular = false,
  }) {
    return TextStyle(
      fontFamily: fontFamily,
      fontFamilyFallback: fontFamilyFallback,
      fontSize: size,
      fontWeight: weight,
      height: height,
      color: color,
      fontFeatures: tabular ? const [FontFeature.tabularFigures()] : null,
    );
  }

  static TextStyle display([Color? color]) =>
      base(size: 28, weight: FontWeight.w600, height: 1.4, color: color);

  static TextStyle title([Color? color]) =>
      base(size: 22, weight: FontWeight.w600, height: 1.4, color: color);

  static TextStyle heading([Color? color]) =>
      base(size: 18, weight: FontWeight.w600, height: 1.4, color: color);

  static TextStyle body([Color? color]) =>
      base(size: 16, weight: FontWeight.w400, height: 1.45, color: color);

  static TextStyle bodySemiBold([Color? color]) =>
      base(size: 16, weight: FontWeight.w600, height: 1.45, color: color);

  static TextStyle label([Color? color]) =>
      base(size: 14, weight: FontWeight.w600, height: 1.4, color: color);

  static TextStyle labelRegular([Color? color]) =>
      base(size: 14, weight: FontWeight.w400, height: 1.4, color: color);

  static TextStyle caption([Color? color]) =>
      base(size: 13, weight: FontWeight.w400, height: 1.4, color: color);

  static TextStyle tabular(TextStyle style) =>
      style.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
}
