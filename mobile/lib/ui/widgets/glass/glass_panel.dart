import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// Frosted glass panel with Golden Hour tint.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.borderRadius = const BorderRadius.all(Radius.circular(24)),
    this.blurSigma = 18,
    this.opacity = 0.72,
  });

  final Widget child;
  final EdgeInsets padding;
  final BorderRadius borderRadius;
  final double blurSigma;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLowest.withValues(alpha: opacity),
            borderRadius: borderRadius,
            border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.45)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x14000000),
                blurRadius: 24,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}
