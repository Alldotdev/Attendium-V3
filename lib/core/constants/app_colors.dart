import 'package:flutter/material.dart';

/// Design tokens for Attendium.
/// Strictly adheres to the white-dominant minimalist academic design directive.
class AppColors {
  AppColors._();

  // Canvas & Backgrounds
  static const Color background = Color(0xFFFFFFFF);
  static const Color canvas = Color(0xFFFFFFFF);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceSubtle = Color(0xFFF9FAFB); // gray-50
  static const Color surfaceMuted = Color(0xFFF3F4F6);  // gray-100
  static const Color surfaceHover = Color(0xFFF0F2F5);

  // Borders & Dividers
  static const Color borderSubtle = Color(0xFFE5E7EB); // gray-200
  static const Color borderMedium = Color(0xFFD1D5DB); // gray-300
  static const Color borderStrong = Color(0xFF9CA3AF); // gray-400

  // Slate Text Hierarchy
  static const Color textPrimary = Color(0xFF111827);   // slate-900 / gray-900
  static const Color textSecondary = Color(0xFF4B5563); // gray-600
  static const Color textMuted = Color(0xFF6B7280);     // gray-500
  static const Color textDisabled = Color(0xFF9CA3AF);  // gray-400
  static const Color textOnAccent = Color(0xFFFFFFFF);

  // Primary Alldotdev Brand Colors (Logo purple & magenta accent)
  static const Color primary = Color(0xFF7E22CE); // Alldotdev rich violet/purple
  static const Color primaryHover = Color(0xFF6B17B8); // Deeper purple hover
  static const Color primaryLight = Color(0xFFF3E8FF); // Soft violet tint for selected rows & tabs
  static const Color primaryDark = Color(0xFF581C87); // Deep navy-purple
  static const Color alldotdevNavy = Color(0xFF0C133B); // Alldotdev signature deep navy
  static const Color alldotdevMagenta = Color(0xFFB800E8); // Alldotdev electric magenta/violet

  // Semantic Colors: Emerald (Present / Safe / Success)
  static const Color present = Color(0xFF10B981); // emerald-500
  static const Color presentLight = Color(0xFFD1FAE5); // emerald-100
  static const Color presentDark = Color(0xFF065F46);
  static const Color presentBg = presentLight;

  // Semantic Colors: Amber (Late / At-Risk / Warning)
  static const Color late = Color(0xFFF59E0B); // amber-500
  static const Color lateLight = Color(0xFFFEF3C7); // amber-100
  static const Color lateDark = Color(0xFF92400E);
  static const Color lateBg = lateLight;

  // Semantic Colors: Red (Absent / Debarred / Danger)
  static const Color absent = Color(0xFFEF4444); // red-500
  static const Color absentLight = Color(0xFFFEE2E2); // red-100
  static const Color absentDark = Color(0xFF991B1B);
  static const Color absentBg = absentLight;

  // Semantic Colors: Sky / Indigo (Excused)
  static const Color excused = Color(0xFF3B82F6); // blue-500
  static const Color excusedLight = Color(0xFFDBEAFE); // blue-100
  static const Color excusedDark = Color(0xFF1E40AF);
  static const Color excusedBg = excusedLight;

  // Semantic Colors: Gray (Unmarked)
  static const Color unmarked = Color(0xFF9CA3AF); // gray-400
  static const Color unmarkedLight = Color(0xFFF3F4F6); // gray-100
  static const Color unmarkedDark = Color(0xFF374151);

  // Shadows
  static const List<BoxShadow> shadowSm = [
    BoxShadow(color: Color(0x0A000000), blurRadius: 4, offset: Offset(0, 1)),
  ];
  static const List<BoxShadow> shadowMd = [
    BoxShadow(color: Color(0x0F000000), blurRadius: 10, offset: Offset(0, 4)),
    BoxShadow(color: Color(0x0A000000), blurRadius: 4, offset: Offset(0, 2)),
  ];
  static const List<BoxShadow> shadowLg = [
    BoxShadow(color: Color(0x14000000), blurRadius: 20, offset: Offset(0, 10)),
    BoxShadow(color: Color(0x0A000000), blurRadius: 8, offset: Offset(0, 4)),
  ];
}
