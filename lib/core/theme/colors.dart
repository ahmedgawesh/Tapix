import 'package:flutter/material.dart';

// Tapix Brand Colors - extracted from logo
class AppColors {
  // Brand Colors (from Tapix logo)
  static const Color brandPrimary = Color(0xFF1976D2);      // Tapix Blue
  static const Color brandSecondary = Color(0xFF0D47A1);    // Dark Blue
  static const Color brandAccent = Color(0xFFFF9800);       // Tapix Orange
  static const Color brandAccentLight = Color(0xFFFFB74D);  // Light Orange
  
  // Primary palette (Blue tones from logo)
  static const Color primary = Color(0xFF1976D2);
  static const Color primaryLight = Color(0xFF42A5F5);
  static const Color primaryDark = Color(0xFF0D47A1);
  static const Color primaryContainer = Color(0xFFBBDEFB);
  
  // Secondary palette (Orange tones from logo)
  static const Color secondary = Color(0xFFFF9800);
  static const Color secondaryLight = Color(0xFFFFB74D);
  static const Color secondaryDark = Color(0xFFF57C00);
  static const Color secondaryContainer = Color(0xFFFFE0B2);
  
  // Semantic Status Colors
  static const Color success = Color(0xFF4CAF50);
  static const Color warning = Color(0xFFFF9800);
  static const Color error = Color(0xFFF44336);
  static const Color info = Color(0xFF2196F3);

  // Neutral Colors
  static const Color surface = Color(0xFFFAFAFA);
  static const Color surfaceDark = Color(0xFF121212);
  static const Color onSurface = Color(0xFF1C1B1F);
  static const Color onSurfaceDark = Color(0xFFE6E1E5);
  
  // High Contrast Overrides (if needed)
  static const Color highContrastError = Color(0xFFB00020);
}
