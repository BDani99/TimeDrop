import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// Frosted glass panel with Golden Hour tint.
///
/// Set [useBlur] to false on screens with a solid background (e.g. Settings)
/// where [BackdropFilter] has no visible effect but costs GPU time every frame.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.borderRadius = const BorderRadius.all(Radius.circular(24)),
    this.blurSigma = 18,
    this.opacity = 0.72,
    this.useBlur = true,
  });

  final Widget child;
  final EdgeInsets padding;
  final BorderRadius borderRadius;
  final double blurSigma;
  final double opacity;

  /// When false, skips [BackdropFilter] entirely — use on solid-colour
  /// backgrounds where blur has no visual effect.
  final bool useBlur;

  @override
  Widget build(BuildContext context) {
    final decoration = BoxDecoration(
      color: AppColors.surfaceContainerLowest.withValues(alpha: useBlur ? opacity : 0.94),
      borderRadius: borderRadius,
      border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.45)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x14000000),
          blurRadius: 24,
          offset: Offset(0, 8),
        ),
      ],
    );

    final inner = DecoratedBox(
      decoration: decoration,
      child: Padding(padding: padding, child: child),
    );

    if (!useBlur) {
      return ClipRRect(borderRadius: borderRadius, child: inner);
    }

    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: inner,
      ),
    );
  }
}
