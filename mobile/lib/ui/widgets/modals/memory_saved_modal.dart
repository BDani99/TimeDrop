import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../glass/glass_bottom_sheet.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/capsule_provider.dart';
import '../../../providers/payment_provider.dart';
import '../../../services/supabase_service.dart';
import '../app_snackbar.dart';
import '../primary_button.dart';

/// Shown after a recipient finishes watching a decrypted memory. Offers to
/// persist it (`saved_memories`) by linking an Apple/Google account — the
/// documented, consent-gated relaxation of Zero-Knowledge described in
/// migration `0005_saved_memories.sql`. Purely additive: skipping this
/// never affects the primary `time_capsules` flow.
class MemorySavedModal extends StatefulWidget {
  const MemorySavedModal({super.key});

  /// Resolves to true when the user asked to see the plans — the caller opens
  /// the paywall.
  ///
  /// The modal deliberately does NOT push the paywall itself: it lives inside
  /// a bottom sheet, so its own `Navigator` is the sheet's. Popping and then
  /// pushing through the same context is how you end up routing off a defunct
  /// element. Returning a result and letting the presenting screen navigate is
  /// the pattern every sheet in the app follows.
  static Future<bool> show(BuildContext context) async {
    final result = await GlassBottomSheet.show<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const MemorySavedModal(),
    );
    return result ?? false;
  }

  @override
  State<MemorySavedModal> createState() => _MemorySavedModalState();
}

class _MemorySavedModalState extends State<MemorySavedModal> {
  bool _isSaving = false;

  /// Subscribers keep memories; reviewers do too, so store review can exercise
  /// the flow.
  bool get _canKeep =>
      context.watch<PaymentProvider>().isSubscribed ||
      context.watch<AuthProvider>().isReviewer;

  Future<void> _saveWith(Future<void> Function() link) async {
    setState(() => _isSaving = true);
    try {
      if (!context.read<AuthProvider>().isLinked) {
        await link();
      }
      await _persistSavedMemory();
      if (!mounted) return;
      AppSnackbar.showSuccess(context, 'Memory kept.');
      Navigator.of(context).pop(false);
    } catch (e) {
      if (!mounted) return;
      AppSnackbar.showError(context, e);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _persistSavedMemory() async {
    final auth = context.read<AuthProvider>();
    final capsule = context.read<CapsuleProvider>();
    final userId = auth.userId;
    final capsuleId = capsule.activeCapsule?.id;
    final key = capsule.pendingEncryptionKey;
    if (userId == null || capsuleId == null || key == null) return;

    await SupabaseService.saveMemory(
      userId: userId,
      capsuleId: capsuleId,
      encryptionKey: key,
    ).timeout(AppConstants.dbCallTimeout);
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
            width: 56,
            height: 56,
            decoration: const BoxDecoration(
              color: AppColors.secondaryContainer,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.favorite, color: AppColors.primary),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Keep this memory.',
            textAlign: TextAlign.center,
            style: AppTypography.headlineMd,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            // Said up front. Asking someone to link an Apple or Google account
            // and only THEN telling them it costs money is a bait-and-switch.
            _canKeep
                ? 'Link your account to save this moment to your keepsake box.'
                : 'Keeping the memories you receive is part of TimeDrop Pro.',
            textAlign: TextAlign.center,
            style: AppTypography.bodyMd.copyWith(color: AppColors.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.md),

          if (!_canKeep) ...[
            PrimaryButton(
              label: 'See plans',
              // The presenting screen opens the paywall — see [show].
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ] else ...[
            PrimaryButton(
              label: 'Continue with Apple',
              isLoading: _isSaving,
              onPressed: () => _saveWith(() => context.read<AuthProvider>().linkApple()),
            ),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton(
              onPressed: _isSaving
                  ? null
                  : () => _saveWith(() => context.read<AuthProvider>().linkGoogle()),
              child: const Text('Continue with Google'),
            ),
          ],

          const SizedBox(height: AppSpacing.xs),
          TextButton(
            onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
            child: const Text('Not now'),
          ),
        ],
      ),
    );
  }
}
