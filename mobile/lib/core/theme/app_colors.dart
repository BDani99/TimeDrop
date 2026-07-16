import 'package:flutter/material.dart';

/// Direct 1:1 mapping of the "Golden Hour" design tokens from
/// `design/DESIGN.md`. Every hex value in that file's YAML front-matter has
/// a matching constant here — do not invent new colors, extend this file.
class AppColors {
  AppColors._();

  static const surface = Color(0xFFFAF9F6);
  static const surfaceDim = Color(0xFFDBDAD7);
  static const surfaceBright = Color(0xFFFAF9F6);
  static const surfaceContainerLowest = Color(0xFFFFFFFF);
  static const surfaceContainerLow = Color(0xFFF4F3F1);
  static const surfaceContainer = Color(0xFFEFEEEB);
  static const surfaceContainerHigh = Color(0xFFE9E8E5);
  static const surfaceContainerHighest = Color(0xFFE3E2E0);

  static const onSurface = Color(0xFF1A1C1A);
  static const onSurfaceVariant = Color(0xFF57423D);
  static const inverseSurface = Color(0xFF2F312F);
  static const inverseOnSurface = Color(0xFFF2F1EE);

  static const outline = Color(0xFF8A716C);
  static const outlineVariant = Color(0xFFDEC0B9);
  static const surfaceTint = Color(0xFFA33D25);

  static const primary = Color(0xFFA33D25);
  static const onPrimary = Color(0xFFFFFFFF);
  static const primaryContainer = Color(0xFFFF8264);
  static const onPrimaryContainer = Color(0xFF731B06);
  static const inversePrimary = Color(0xFFFFB4A3);

  static const secondary = Color(0xFF7C5637);
  static const onSecondary = Color(0xFFFFFFFF);
  static const secondaryContainer = Color(0xFFFECAA3);
  static const onSecondaryContainer = Color(0xFF795334);

  static const tertiary = Color(0xFFA03F30);
  static const onTertiary = Color(0xFFFFFFFF);
  static const tertiaryContainer = Color(0xFFFB8470);
  static const onTertiaryContainer = Color(0xFF711D12);

  static const error = Color(0xFFBA1A1A);
  static const onError = Color(0xFFFFFFFF);
  static const errorContainer = Color(0xFFFFDAD6);
  static const onErrorContainer = Color(0xFF93000A);

  static const primaryFixed = Color(0xFFFFDAD2);
  static const primaryFixedDim = Color(0xFFFFB4A3);
  static const onPrimaryFixed = Color(0xFF3D0700);
  static const onPrimaryFixedVariant = Color(0xFF832610);

  static const secondaryFixed = Color(0xFFFFDCC3);
  static const secondaryFixedDim = Color(0xFFEFBC96);
  static const onSecondaryFixed = Color(0xFF2F1500);
  static const onSecondaryFixedVariant = Color(0xFF623F22);

  static const tertiaryFixed = Color(0xFFFFDAD4);
  static const tertiaryFixedDim = Color(0xFFFFB4A7);
  static const onTertiaryFixed = Color(0xFF400200);
  static const onTertiaryFixedVariant = Color(0xFF80281B);

  static const background = Color(0xFFFAF9F6);
  static const onBackground = Color(0xFF1A1C1A);
  static const surfaceVariant = Color(0xFFE3E2E0);

  /// Warm, muted gold for ritual animations (seal, unlock, share). A softer,
  /// lower-saturation tone than raw `#FFD700`, matching the Golden Hour mood.
  static const ritualGold = Color(0xFFE3B778);
}
