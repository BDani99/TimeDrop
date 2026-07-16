import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../glass/glass_bottom_sheet.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/capsule_provider.dart';
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

  static Future<void> show(BuildContext context) {
    return GlassBottomSheet.show(
      context: context,
      isScrollControlled: true,
      builder: (_) => const MemorySavedModal(),
    );
  }

  @override
  State<MemorySavedModal> createState() => _MemorySavedModalState();
}

class _MemorySavedModalState extends State<MemorySavedModal> {
  bool _isSaving = false;

  Future<void> _saveWith(Future<void> Function() link) async {
    setState(() => _isSaving = true);
    try {
      final auth = context.read<AuthProvider>();
      if (!auth.isLinked) {
        await link();
      }
      await _persistSavedMemory();
      if (!mounted) return;
      AppSnackbar.showSuccess(context, 'Memory saved forever.');
      Navigator.of(context).pop();
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
            'Keep this memory forever.',
            textAlign: TextAlign.center,
            style: AppTypography.headlineMd,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Link your account to save this moment safely to your digital keepsake box.',
            textAlign: TextAlign.center,
            style: AppTypography.bodyMd.copyWith(color: AppColors.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.md),
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
          const SizedBox(height: AppSpacing.xs),
          TextButton(
            onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
            child: const Text('Not now'),
          ),
        ],
      ),
    );
  }
}
