import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'colors.dart';

class AppTheme {
  static ThemeData lightTheme = FlexThemeData.light(
    scheme: FlexScheme.materialBaseline,
    useMaterial3: true,
    useMaterial3ErrorColors: true,
    visualDensity: VisualDensity.standard,
    fontFamily: 'IBMPlexSansArabic',
    // Custom colors
    colors: const FlexSchemeColor(
      primary: AppColors.brandPrimary,
      primaryContainer: Color(0xFFEADDFF),
      secondary: Color(0xFF625B71),
      secondaryContainer: Color(0xFFE8DEF8),
      tertiary: Color(0xFF7D5260),
      tertiaryContainer: Color(0xFFFFD8E4),
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
    ),
    keyColors: const FlexKeyColors(
      useSecondary: true,
      useTertiary: true,
      keepPrimary: true,
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
    scheme: FlexScheme.materialBaseline,
    useMaterial3: true,
    useMaterial3ErrorColors: true,
    visualDensity: VisualDensity.standard,
    fontFamily: 'IBMPlexSansArabic',
    // Custom colors
    colors: const FlexSchemeColor(
      primary: Color(0xFFD0BCFF),
      primaryContainer: Color(0xFF4F378B),
      secondary: Color(0xFFCCC2DC),
      secondaryContainer: Color(0xFF4A4458),
      tertiary: Color(0xFFEFB8C8),
      tertiaryContainer: Color(0xFF633B48),
      appBarColor: Color(0xFF1C1B1F),
      error: Color(0xFFF2B8B5),
    ),
    subThemesData: const FlexSubThemesData(
      blendOnLevel: 20,
      useMaterial3Typography: true,
      useM2StyleDividerInM3: true,
      alignedDropdown: true,
      useInputDecoratorThemeInDialogs: true,
    ),
    keyColors: const FlexKeyColors(
      useSecondary: true,
      useTertiary: true,
      keepPrimary: true,
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
