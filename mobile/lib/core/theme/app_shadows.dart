import 'package:flutter/material.dart';

import 'app_colors.dart';

/// "Ambient Glow" shadows per `design/DESIGN.md`: low opacity (10-15%),
/// large blur (30-50px), tinted with Sunset Orange/Terracotta — never a
/// harsh grey shadow.
class AppShadows {
  AppShadows._();

  static List<BoxShadow> ambient({
    Color tint = AppColors.primary,
    double opacity = 0.12,
    double blurRadius = 40,
  }) {
    return [
      BoxShadow(
        color: tint.withValues(alpha: opacity),
        blurRadius: blurRadius,
        spreadRadius: 0,
        offset: const Offset(0, 8),
      ),
    ];
  }

  static List<BoxShadow> get card => ambient();

  static List<BoxShadow> get cardStrong =>
      ambient(opacity: 0.16, blurRadius: 50);
}
