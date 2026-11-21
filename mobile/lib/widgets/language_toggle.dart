import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../theme/tokens.dart';

class LanguageToggle extends StatelessWidget {
  const LanguageToggle({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final AppLanguage selected;
  final ValueChanged<AppLanguage> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(
        color: tokens.surfaceRaised,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(
          color: tokens.outline,
          width: AppSizes.borderWidth,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: AppLanguage.values.map((lang) {
          final isSelected = lang == selected;
          return Semantics(
            button: true,
            selected: isSelected,
            label: lang.displayName,
            child: InkWell(
              key: ValueKey('lang_${lang.code}'),
              onTap: () => onChanged(lang),
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: AnimatedContainer(
                duration: reduceMotion ? Duration.zero : AppMotion.fast,
                curve: AppMotion.curve,
                constraints: const BoxConstraints(
                  minWidth: 40,
                  minHeight: 40,
                ),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: isSelected ? tokens.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text(
                  lang.shortLabel,
                  style: AppTypography.label(
                    isSelected ? Colors.white : tokens.inkMuted,
                  ).copyWith(
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
