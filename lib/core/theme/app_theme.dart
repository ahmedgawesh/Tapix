import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'colors.dart';

class AppTheme {
  static ThemeData lightTheme = FlexThemeData.light(
    useMaterial3: true,
    useMaterial3ErrorColors: true,
    visualDensity: VisualDensity.standard,
    fontFamily: 'IBMPlexSansArabic',
    // Tapix Brand Colors (Blue & Orange from logo)
    colors: const FlexSchemeColor(
      primary: AppColors.primary,                    // Tapix Blue
      primaryContainer: AppColors.primaryContainer,  // Light Blue
      secondary: AppColors.secondary,                // Tapix Orange
      secondaryContainer: AppColors.secondaryContainer, // Light Orange
      tertiary: AppColors.primaryDark,               // Dark Blue
      tertiaryContainer: Color(0xFFBBDEFB),
      appBarColor: AppColors.surface,
      error: AppColors.error,
    ),
    subThemesData: const FlexSubThemesData(
      blendOnLevel: 10,
      blendOnColors: false,
      useMaterial3Typography: true,
      useM2StyleDividerInM3: true,
      alignedDropdown: true,
      useInputDecoratorThemeInDialogs: true,
      filledButtonRadius: 12,
      elevatedButtonRadius: 12,
      outlinedButtonRadius: 12,
      inputDecoratorRadius: 12,
      cardRadius: 16,
    ),
    keyColors: const FlexKeyColors(
      useSecondary: true,
      useTertiary: true,
      keepPrimary: true,
      keepSecondary: true,
    ),
    tones: FlexTones.material(Brightness.light),
    extensions: [
      const SemanticColorsExtension(
        success: AppColors.success,
        warning: AppColors.warning,
        info: AppColors.info,
      ),
    ],
  );

  static ThemeData darkTheme = FlexThemeData.dark(
    useMaterial3: true,
    useMaterial3ErrorColors: true,
    visualDensity: VisualDensity.standard,
    fontFamily: 'IBMPlexSansArabic',
    // Tapix Brand Colors (Blue & Orange from logo) - Dark mode variants
    colors: const FlexSchemeColor(
      primary: AppColors.primaryLight,               // Lighter Blue for dark mode
      primaryContainer: AppColors.primaryDark,       // Dark Blue container
      secondary: AppColors.secondaryLight,           // Lighter Orange for dark mode
      secondaryContainer: AppColors.secondaryDark,   // Dark Orange container
      tertiary: Color(0xFF90CAF9),                   // Light Blue accent
      tertiaryContainer: Color(0xFF1565C0),
      appBarColor: AppColors.surfaceDark,
      error: Color(0xFFF2B8B5),
    ),
    subThemesData: const FlexSubThemesData(
      blendOnLevel: 20,
      useMaterial3Typography: true,
      useM2StyleDividerInM3: true,
      alignedDropdown: true,
      useInputDecoratorThemeInDialogs: true,
      filledButtonRadius: 12,
      elevatedButtonRadius: 12,
      outlinedButtonRadius: 12,
      inputDecoratorRadius: 12,
      cardRadius: 16,
    ),
    keyColors: const FlexKeyColors(
      useSecondary: true,
      useTertiary: true,
      keepPrimary: true,
      keepSecondary: true,
    ),
    tones: FlexTones.material(Brightness.dark),
    extensions: [
      const SemanticColorsExtension(
        success: AppColors.success,
        warning: AppColors.warning,
        info: AppColors.info,
      ),
    ],
  );
}

// Theme Extension for Semantic Colors
@immutable
class SemanticColorsExtension extends ThemeExtension<SemanticColorsExtension> {
  const SemanticColorsExtension({
    required this.success,
    required this.warning,
    required this.info,
  });

  final Color success;
  final Color warning;
  final Color info;

  @override
  SemanticColorsExtension copyWith({
    Color? success,
    Color? warning,
    Color? info,
  }) {
    return SemanticColorsExtension(
      success: success ?? this.success,
      warning: warning ?? this.warning,
      info: info ?? this.info,
    );
  }

  @override
  SemanticColorsExtension lerp(
      ThemeExtension<SemanticColorsExtension>? other, double t) {
    if (other is! SemanticColorsExtension) {
      return this;
    }
    return SemanticColorsExtension(
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      info: Color.lerp(info, other.info, t)!,
    );
  }
}
