import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../providers/drop_balance_provider.dart';

/// How many drops the user has left, on the Home header.
///
/// Without this the only place the balance appears is the paywall, so someone
/// finds out they are out of drops at the worst possible moment — after
/// recording. Tapping opens the paywall.
///
/// Renders nothing until a real balance has arrived: a placeholder zero would
/// tell a paying user they have nothing.
class DropBalanceChip extends StatelessWidget {
  const DropBalanceChip({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final drops = context.watch<DropBalanceProvider>();
    if (!drops.isLoaded) return const SizedBox.shrink();

    final state = drops.state;
    final isEmpty = !state.isReviewer && state.totalRemaining == 0;

    final label = state.isReviewer
        ? 'Reviewer access'
        : state.totalRemaining == 1
            ? '1 drop left'
            : '${state.totalRemaining} drops left';

    // An empty balance is the one case worth colouring differently — it is the
    // only state the user has to act on.
    final foreground =
        isEmpty ? AppColors.error : AppColors.onSecondaryContainer;
    final background = isEmpty
        ? AppColors.errorContainer
        : AppColors.secondaryContainer;

    return Semantics(
      button: true,
      label: '$label. Tap to get more drops.',
      child: InkWell(
        customBorder: AppRadii.pill,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: 5,
          ),
          decoration: ShapeDecoration(color: background, shape: AppRadii.pill),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                state.isReviewer
                    ? Icons.verified_outlined
                    : Icons.confirmation_number_outlined,
                size: 14,
                color: foreground,
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: AppTypography.labelSm.copyWith(color: foreground),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
