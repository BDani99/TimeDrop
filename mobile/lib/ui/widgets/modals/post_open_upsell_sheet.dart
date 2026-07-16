import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../glass/glass_bottom_sheet.dart';
import '../primary_button.dart';
import 'memory_saved_modal.dart';

/// What the recipient chose on the post-open upsell.
enum UpsellResult { paywall, dismissed }

/// The conversion hook shown right after a recipient finishes watching a
/// memory (video + photos) — the highest emotional moment. Instead of
/// dropping them back to the app, it invites them to create their own.
/// Replaces the old direct `MemorySavedModal` call on "Done"; the "save this
/// memory" path is still reachable here as a secondary action.
class PostOpenUpsellSheet extends StatelessWidget {
  const PostOpenUpsellSheet({super.key});

  static Future<UpsellResult?> show(BuildContext context) {
    return GlassBottomSheet.show<UpsellResult>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const PostOpenUpsellSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.primary, AppColors.secondaryContainer],
              ),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.hourglass_bottom, color: Colors.white, size: 30),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'This memory will live forever.',
            textAlign: TextAlign.center,
            style: AppTypography.headlineMd,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Now imagine sending one yourself — sealed in time, waiting for the perfect moment to open.',
            textAlign: TextAlign.center,
            style: AppTypography.bodyMd.copyWith(color: AppColors.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.md),
          PrimaryButton(
            label: 'Unlock Lifetime Vault',
            onPressed: () => Navigator.of(context).pop(UpsellResult.paywall),
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton(
            onPressed: () async {
              await MemorySavedModal.show(context);
              if (context.mounted) Navigator.of(context).pop(UpsellResult.dismissed);
            },
            child: const Text('Save this memory'),
          ),
          const SizedBox(height: AppSpacing.xs),
          TextButton(
            onPressed: () => Navigator.of(context).pop(UpsellResult.dismissed),
            child: const Text('Not now'),
          ),
        ],
      ),
    );
  }
}
