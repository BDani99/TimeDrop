import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../core/theme/app_colors.dart';

/// Shimmer skeleton placeholder replacing spinners during data loads.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    this.width,
    this.height = 16,
    this.borderRadius = 12,
  });

  final double? width;
  final double height;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    )
        .animate(onPlay: (c) => c.repeat())
        .shimmer(
          duration: 1600.ms,
          color: AppColors.surfaceContainerLowest.withValues(alpha: 0.45),
        );
  }
}

class SkeletonMemoryCard extends StatelessWidget {
  const SkeletonMemoryCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonBox(width: 120, height: 20, borderRadius: 8),
          SizedBox(height: 12),
          SkeletonBox(width: double.infinity, height: 14),
          SizedBox(height: 8),
          SkeletonBox(width: 180, height: 14),
        ],
      ),
    );
  }
}
