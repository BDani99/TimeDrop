import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../providers/auth_provider.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/glass/glass_panel.dart';
import '../widgets/primary_button.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isBusy = false;

  Future<void> _runGuarded(Future<void> Function() action) async {
    setState(() => _isBusy = true);
    try {
      await action();
      if (!mounted) return;
      AppSnackbar.showSuccess(context, 'Account linked.');
    } catch (e) {
      if (!mounted) return;
      AppSnackbar.showError(context, e);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _confirmDeleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete account?'),
        content: const Text(
          'This signs you out of this device. Memories tied to this account may no longer be reachable from here.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await context.read<AuthProvider>().deleteAccount();
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      if (!mounted) return;
      AppSnackbar.showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.containerMargin),
        children: [
          // ── Account ────────────────────────────────────────────────────────
          GlassPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  const Icon(Icons.person_outline, color: AppColors.primary),
                  const SizedBox(width: AppSpacing.sm),
                  Text('Account', style: AppTypography.headlineMd),
                ]),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  auth.isLinked
                      ? 'Your account is linked and your memories are safely backed up.'
                      : 'You\'re using an anonymous, device-only account. Link Apple or Google to keep your memories safe across devices.',
                  style: AppTypography.bodyMd.copyWith(color: AppColors.onSurfaceVariant),
                ),
                if (!auth.isLinked) ...[
                  const SizedBox(height: AppSpacing.md),
                  PrimaryButton(
                    label: 'Continue with Apple',
                    isLoading: _isBusy,
                    onPressed: () => _runGuarded(() => context.read<AuthProvider>().linkApple()),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  OutlinedButton(
                    onPressed: _isBusy
                        ? null
                        : () => _runGuarded(() => context.read<AuthProvider>().linkGoogle()),
                    child: const Text('Continue with Google'),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // ── Danger zone ────────────────────────────────────────────────────
          GlassPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  const Icon(Icons.warning_amber_outlined, color: AppColors.error),
                  const SizedBox(width: AppSpacing.sm),
                  Text('Privacy', style: AppTypography.headlineMd),
                ]),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Deleting your account signs you out of this device. Memories may no longer be reachable.',
                  style: AppTypography.bodyMd.copyWith(color: AppColors.onSurfaceVariant),
                ),
                const SizedBox(height: AppSpacing.sm),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    side: const BorderSide(color: AppColors.error),
                  ),
                  onPressed: _confirmDeleteAccount,
                  child: const Text('Delete account'),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // ── About ──────────────────────────────────────────────────────────
          GlassPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  const Icon(Icons.info_outline, color: AppColors.onSurfaceVariant),
                  const SizedBox(width: AppSpacing.sm),
                  Text('About', style: AppTypography.headlineMd),
                ]),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('TimeDrop', style: AppTypography.bodyMd),
                    Text(
                      AppConstants.appVersion,
                      style: AppTypography.labelSm.copyWith(color: AppColors.onSurfaceVariant),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Convenience navigator entry point used from HomeScreen.
void openSettingsScreen(BuildContext context) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
}
