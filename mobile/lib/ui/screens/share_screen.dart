import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../services/clipboard_service.dart';
import '../../services/share_service.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/primary_button.dart';

/// "Moment Sealed" confirmation screen shown right after a capsule is
/// created — shows the share code + lets the sender copy/share the link.
class ShareScreen extends StatelessWidget {
  const ShareScreen({super.key, required this.shareId, required this.encryptionKey});

  final String shareId;
  final String encryptionKey;

  @override
  Widget build(BuildContext context) {
    final url = ShareService.buildShareUrl(shareId: shareId, encryptionKey: encryptionKey);
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.containerMargin),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.check_circle, color: AppColors.primary, size: 72),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Memory Sealed',
                style: AppTypography.headlineLg,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Your memory is safely hidden and ready to be shared with someone special.',
                style: AppTypography.bodyMd.copyWith(color: AppColors.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.lg),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppColors.outlineVariant),
                ),
                child: Column(
                  children: [
                    Text('SHARE CODE', style: AppTypography.labelSm),
                    const SizedBox(height: AppSpacing.xs),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          shareId,
                          style: AppTypography.headlineMd.copyWith(fontFamily: 'monospace'),
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy, color: AppColors.primary),
                          onPressed: () async {
                            try {
                              await ClipboardService.copyToClipboard(shareId);
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
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              PrimaryButton(
                label: 'Send to your loved one',
                onPressed: () async {
                  try {
                    await ShareService.shareCapsuleLink(url);
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
            ],
          ),
        ),
      ),
    );
  }
}
