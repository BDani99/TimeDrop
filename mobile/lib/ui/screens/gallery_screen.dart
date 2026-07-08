import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';
import '../../models/received_capsule_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/gallery_provider.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/countdown_timer.dart';
import '../widgets/primary_button.dart';
import 'radar_screen.dart';
import 'video_player_screen.dart';

/// Recipient-side "Gallery": memories received but still locked ("Waiting"),
/// memories already unlocked and available to rewatch ("Unlocked"), and a
/// manual code/link entry field for when clipboard auto-detect didn't fire.
/// Works identically for anonymous accounts — everything here is keyed by
/// the current `auth.uid()`, linked or not.
class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  final _codeController = TextEditingController();
  bool _isSubmittingCode = false;
  bool _isReopening = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  String? get _userId => context.read<AuthProvider>().userId;

  Future<void> _load() async {
    final userId = _userId;
    if (userId == null) return;
    try {
      await context.read<GalleryProvider>().load(userId);
    } catch (e) {
      if (mounted) AppSnackbar.showError(context, e);
    }
  }

  Future<void> _submitCode() async {
    final userId = _userId;
    if (userId == null) return;
    final input = _codeController.text;
    setState(() => _isSubmittingCode = true);
    try {
      final link = await context.read<GalleryProvider>().submitCode(input, userId: userId);
      if (!mounted) return;
      _codeController.clear();
      FocusScope.of(context).unfocus();
      if (link != null) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => RadarScreen(shareId: link.shareId, encryptionKey: link.encryptionKey),
          ),
        );
      } else {
        AppSnackbar.showSuccess(context, 'Added to your gallery — waiting to unlock.');
      }
    } catch (e) {
      if (mounted) AppSnackbar.showError(context, e);
    } finally {
      if (mounted) setState(() => _isSubmittingCode = false);
    }
  }

  Future<void> _openWaiting(ReceivedCapsuleModel item) async {
    if (!item.hasKey) {
      AppSnackbar.showMessage(
        context,
        'You need the full link to open this — ask the sender to resend it.',
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RadarScreen(shareId: item.shareId, encryptionKey: item.encryptionKey!),
      ),
    );
  }

  Future<void> _reopenUnlocked(ReceivedCapsuleModel item) async {
    setState(() => _isReopening = true);
    try {
      final (mediaBytes, mimeType) = await context.read<GalleryProvider>().reopen(item);
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => VideoPlayerScreen(mediaBytes: mediaBytes, mimeType: mimeType),
        ),
      );
    } catch (e) {
      if (mounted) AppSnackbar.showError(context, e);
    } finally {
      if (mounted) setState(() => _isReopening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final gallery = context.watch<GalleryProvider>();

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: const Text('Gallery')),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.containerMargin),
          children: [
            Text('Have a code or link?', style: AppTypography.headlineMd),
            const SizedBox(height: AppSpacing.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _codeController,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(hintText: 'Paste link or enter code'),
                    onSubmitted: (_) => _submitCode(),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                SizedBox(
                  height: 52,
                  child: PrimaryButton(
                    label: 'Add',
                    isLoading: _isSubmittingCode,
                    onPressed: _submitCode,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('Waiting', style: AppTypography.headlineMd),
            const SizedBox(height: AppSpacing.sm),
            if (gallery.isLoading)
              const Center(child: CircularProgressIndicator(color: AppColors.primary))
            else if (gallery.waiting.isEmpty)
              Text(
                'Nothing waiting yet — memories others send you will show up here.',
                style: AppTypography.bodyMd.copyWith(color: AppColors.onSurfaceVariant),
              )
            else
              for (final item in gallery.waiting) ...[
                _WaitingCard(item: item, onTap: () => _openWaiting(item)),
                const SizedBox(height: AppSpacing.sm),
              ],
            const SizedBox(height: AppSpacing.lg),
            Text('Unlocked', style: AppTypography.headlineMd),
            const SizedBox(height: AppSpacing.sm),
            if (!gallery.isLoading && gallery.unlocked.isEmpty)
              Text(
                'Memories you\'ve opened will stay here so you can watch them again.',
                style: AppTypography.bodyMd.copyWith(color: AppColors.onSurfaceVariant),
              )
            else
              for (final item in gallery.unlocked) ...[
                _UnlockedCard(
                  item: item,
                  isBusy: _isReopening,
                  onTap: () => _reopenUnlocked(item),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
          ],
        ),
      ),
    );
  }
}

class _WaitingCard extends StatelessWidget {
  const _WaitingCard({required this.item, required this.onTap});

  final ReceivedCapsuleModel item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: memoryCardDecoration(),
        child: Row(
          children: [
            Icon(
              item.hasKey ? Icons.lock_clock_outlined : Icons.link_off,
              color: AppColors.primary,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.shareId, style: AppTypography.labelMd),
                  const SizedBox(height: 2),
                  if (!item.hasKey)
                    Text(
                      'Missing the full link',
                      style: AppTypography.labelSm.copyWith(color: AppColors.error),
                    )
                  else if (item.isUnlockTimeReached)
                    Text('Ready to open', style: AppTypography.labelSm)
                  else
                    CountdownTimer(target: item.unlockTime),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

class _UnlockedCard extends StatelessWidget {
  const _UnlockedCard({required this.item, required this.isBusy, required this.onTap});

  final ReceivedCapsuleModel item;
  final bool isBusy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: isBusy ? null : onTap,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: memoryCardDecoration(),
        child: Row(
          children: [
            const Icon(Icons.play_circle_outline, color: AppColors.primary),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(item.shareId, style: AppTypography.labelMd),
            ),
            if (isBusy)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
              )
            else
              const Icon(Icons.chevron_right, color: AppColors.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
