import 'package:flutter/material.dart';

import '../../core/haptics/app_haptics.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../services/clipboard_service.dart';
import '../../services/share_service.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/glass/glass_panel.dart';
import '../widgets/primary_button.dart';
import '../widgets/rituals/crystal_share_orb.dart';

/// "Moment Sealed" confirmation screen shown right after a capsule is
/// created — the code, then the link.
///
/// The code leads because it is the part a person can read out, write down or
/// retype, and because a link pasted into a chat app is the thing most likely
/// to arrive broken. Sending the link is still the one-tap path, and it is
/// still what carries the key when [codeUnlock] is false.
class ShareScreen extends StatelessWidget {
  const ShareScreen({
    super.key,
    required this.shareId,
    required this.encryptionKey,
    this.fromName,
    this.codeUnlock = false,
  });

  final String shareId;
  final String encryptionKey;
  final String? fromName;

  /// The sender allowed this drop to be opened with the code alone.
  final bool codeUnlock;

  @override
  Widget build(BuildContext context) {
    final url = ShareService.buildShareUrl(
      shareId: shareId,
      encryptionKey: encryptionKey,
      fromName: fromName,
    );
    final screenH = MediaQuery.sizeOf(context).height;
    final orbScale = screenH < 700 ? 0.85 : 1.0;

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.containerMargin),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight - AppSpacing.containerMargin * 2),
                child: IntrinsicHeight(
                  child: Column(
                    children: [
                      const Spacer(flex: 1),
                      Transform.scale(
                        scale: orbScale,
                        child: CrystalShareOrb(shareId: shareId),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Text(
                        'Your drop is sealed.',
                        style: AppTypography.headlineLg,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'This memory now exists only for one person.',
                        style: AppTypography.bodyMd.copyWith(color: AppColors.onSurfaceVariant),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      GlassPanel(
                        child: Column(
                          children: [
                            Text(
                              'Their code',
                              style: AppTypography.labelSm
                                  .copyWith(color: AppColors.onSurfaceVariant),
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Row(
                              children: [
                                const SizedBox(width: 48),
                                Expanded(
                                  child: Text(
                                    shareId,
                                    textAlign: TextAlign.center,
                                    style: AppTypography.headlineLg.copyWith(
                                      fontFamily: 'monospace',
                                      letterSpacing: 4,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.copy,
                                      color: AppColors.primary),
                                  onPressed: () async {
                                    try {
                                      await ClipboardService.copyToClipboard(
                                          shareId);
                                      await AppHaptics.medium();
                                      if (context.mounted) {
                                        AppSnackbar.showMessage(
                                            context, 'Code copied.');
                                      }
                                    } catch (e) {
                                      if (context.mounted) {
                                        AppSnackbar.showError(context, e);
                                      }
                                    }
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              codeUnlock
                                  ? 'They can type this straight into TimeDrop.'
                                  : 'This finds the memory. To open it, they '
                                      'also need the link below.',
                              textAlign: TextAlign.center,
                              style: AppTypography.labelSm
                                  .copyWith(color: AppColors.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      PrimaryButton(
                        label: 'Send the link',
                        onPressed: () async {
                          try {
                            await ShareService.shareCapsuleLink(url);
                            await AppHaptics.medium();
                          } catch (e) {
                            if (context.mounted) AppSnackbar.showError(context, e);
                          }
                        },
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'Opens straight into their TimeDrop.',
                        textAlign: TextAlign.center,
                        style: AppTypography.labelSm
                            .copyWith(color: AppColors.onSurfaceVariant),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      TextButton(
                        onPressed: () => Navigator.popUntil(context, (route) => route.isFirst),
                        // "Dashboard" is a screen this app does not have.
                        child: const Text('Back to home'),
                      ),
                      const Spacer(flex: 1),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
