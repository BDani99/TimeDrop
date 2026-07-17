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
/// created — shows the share code + lets the sender copy/share the link.
class ShareScreen extends StatelessWidget {
  const ShareScreen({
    super.key,
    required this.shareId,
    required this.encryptionKey,
    this.fromName,
  });

  final String shareId;
  final String encryptionKey;
  final String? fromName;

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
                        'Your capsule is sealed!',
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
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                shareId,
                                textAlign: TextAlign.center,
                                style: AppTypography.headlineMd.copyWith(fontFamily: 'monospace'),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.copy, color: AppColors.primary),
                              onPressed: () async {
                                try {
                                  await ClipboardService.copyToClipboard(shareId);
                                  await AppHaptics.medium();
                                  if (context.mounted) {
                                    AppSnackbar.showMessage(context, 'Copied!');
                                  }
                                } catch (e) {
                                  if (context.mounted) AppSnackbar.showError(context, e);
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      PrimaryButton(
                        label: 'Send to your loved one',
                        onPressed: () async {
                          try {
                            await ShareService.shareCapsuleLink(url);
                            await AppHaptics.medium();
                          } catch (e) {
                            if (context.mounted) AppSnackbar.showError(context, e);
                          }
                        },
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      TextButton(
                        onPressed: () => Navigator.popUntil(context, (route) => route.isFirst),
                        child: const Text('Return to Dashboard'),
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
