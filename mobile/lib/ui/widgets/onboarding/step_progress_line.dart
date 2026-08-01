import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// A single hairline that fills as the user advances.
///
/// Deliberately one bar rather than a segment per page: at nine steps, discrete
/// segments read as a long list of chores.
class StepProgressLine extends StatelessWidget {
  const StepProgressLine({
    super.key,
    required this.step,
    required this.totalSteps,
  });

  /// 1-based.
  final int step;
  final int totalSteps;

  @override
  Widget build(BuildContext context) {
    final progress = (step / totalSteps).clamp(0.0, 1.0);

    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          height: 3,
          decoration: BoxDecoration(
            color: AppColors.outlineVariant.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(2),
          ),
          alignment: Alignment.centerLeft,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            width: constraints.maxWidth * progress,
            height: 3,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        );
      },
    );
  }
}
