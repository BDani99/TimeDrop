import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// Typography scale from `design/DESIGN.md`: Playfair Display (serif) for
/// headlines/display, Plus Jakarta Sans for body/labels.
class AppTypography {
  AppTypography._();

  static TextStyle get displayLg => GoogleFonts.playfairDisplay(
        fontSize: 48,
        fontWeight: FontWeight.w700,
        height: 1.1,
        letterSpacing: -0.02 * 48,
        color: AppColors.onSurface,
      );

  static TextStyle get headlineLg => GoogleFonts.playfairDisplay(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        height: 1.2,
        color: AppColors.onSurface,
      );

  static TextStyle get headlineLgMobile => GoogleFonts.playfairDisplay(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        height: 1.2,
        color: AppColors.onSurface,
      );

  static TextStyle get headlineMd => GoogleFonts.playfairDisplay(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        height: 1.3,
        color: AppColors.onSurface,
      );

  static TextStyle get bodyLg => GoogleFonts.plusJakartaSans(
        fontSize: 18,
        fontWeight: FontWeight.w400,
        height: 1.6,
        color: AppColors.onSurface,
      );

  static TextStyle get bodyMd => GoogleFonts.plusJakartaSans(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        height: 1.6,
        color: AppColors.onSurface,
      );

  static TextStyle get labelMd => GoogleFonts.plusJakartaSans(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        height: 1.4,
        letterSpacing: 0.01 * 14,
        color: AppColors.onSurfaceVariant,
      );

  static TextStyle get labelSm => GoogleFonts.plusJakartaSans(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        height: 1.4,
        color: AppColors.onSurfaceVariant,
      );
}
