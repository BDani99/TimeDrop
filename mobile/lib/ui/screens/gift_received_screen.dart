import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/errors/app_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../models/capsule_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/presented_shares_service.dart';
import '../../services/supabase_service.dart';
import '../router/app_router.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/countdown_timer.dart';
import '../widgets/loading/skeleton_box.dart';
import '../widgets/navigation/spring_page_route.dart';
import '../widgets/primary_button.dart';
import 'radar_screen.dart';

/// First-touch receive experience: emotional intro + countdown (or Open now).
/// No map, radar, or media. Marks the shareId as presented so clipboard
/// auto-open won't fire again on subsequent launches.
class GiftReceivedScreen extends StatefulWidget {
  const GiftReceivedScreen({
    super.key,
    required this.shareId,
    required this.encryptionKey,
    this.fromName,
  });

  final String shareId;
  final String encryptionKey;
  final String? fromName;

  @override
  State<GiftReceivedScreen> createState() => _GiftReceivedScreenState();
}

class _GiftReceivedScreenState extends State<GiftReceivedScreen> {
  CapsuleModel? _capsule;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    final userId = context.read<AuthProvider>().userId;
    try {
      await PresentedSharesService.markPresented(widget.shareId);
      // Clear clipboard so resume/bootstrap doesn't re-detect this link.
      try {
        await Clipboard.setData(const ClipboardData(text: ''));
      } catch (_) {}

      if (userId == null) {
        throw const AuthException('You need to be signed in to receive this memory.');
      }

      final capsule = await SupabaseService.fetchCapsuleByShareId(widget.shareId);
      if (capsule == null) {
        throw const CapsuleException('This memory could not be found.');
      }

      await SupabaseService.upsertReceivedCapsule(
        userId: userId,
        capsuleId: capsule.id,
        shareId: capsule.shareId,
        unlockTime: capsule.unlockTime,
        latitude: capsule.latitude,
        longitude: capsule.longitude,
        encryptionKey: widget.encryptionKey,
        fromName: widget.fromName,
        capsuleCreatedAt: capsule.createdAt,
      );

      if (!mounted) return;
      setState(() {
        _capsule = capsule;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
      AppSnackbar.showError(context, e);
    }
  }

  bool get _isReady {
    final c = _capsule;
    if (c == null) return false;
    return c.isUnlocked && !c.isPending;
  }

  void _saveToVault() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      enterAppAfterRecipient(context);
    }
  }

  void _openNow() {
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pushReplacement(
        SpringPageRoute(
          page: RadarScreen(
            shareId: widget.shareId,
            encryptionKey: widget.encryptionKey,
            fromName: widget.fromName,
          ),
        ),
      );
    } else {
      nav.pushAndRemoveUntil(
        SpringPageRoute(
          page: RadarScreen(
            shareId: widget.shareId,
            encryptionKey: widget.encryptionKey,
            fromName: widget.fromName,
          ),
        ),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final from = widget.fromName?.trim();
    final canPop = Navigator.of(context).canPop();

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(canPop ? Icons.arrow_back : Icons.close),
          onPressed: _saveToVault,
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.containerMargin),
          child: _loading
              ? const _GiftSkeleton()
              : _failed
                  ? _GiftError(onClose: _saveToVault)
                  : Column(
                      children: [
                        const Spacer(flex: 2),
                        Icon(
                          Icons.hourglass_bottom_rounded,
                          size: 56,
                          color: AppColors.primary.withValues(alpha: 0.85),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        Text(
                          'Someone left you a memory',
                          textAlign: TextAlign.center,
                          style: AppTypography.headlineLg,
                        ),
                        if (from != null && from.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            'from $from',
                            textAlign: TextAlign.center,
                            style: AppTypography.bodyMd.copyWith(
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                        ],
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          _isReady
                              ? 'It\'s ready to discover — find the place and open it.'
                              : 'It isn\'t open yet. When the time comes, find it in your Vault.',
                          textAlign: TextAlign.center,
                          style: AppTypography.bodyMd.copyWith(
                            color: AppColors.onSurfaceVariant,
                          ),
                        ),
                        if (!_isReady && _capsule != null) ...[
                          const SizedBox(height: AppSpacing.xl),
                          CountdownTimer(target: _capsule!.unlockTime),
                        ],
                        const Spacer(flex: 3),
                        if (_isReady)
                          PrimaryButton(
                            label: 'Open now',
                            onPressed: _openNow,
                          )
                        else
                          PrimaryButton(
                            label: 'Saved to your Vault',
                            onPressed: _saveToVault,
                          ),
                        const SizedBox(height: AppSpacing.sm),
                        if (_isReady)
                          TextButton(
                            onPressed: _saveToVault,
                            child: Text(
                              'Save for later',
                              style: AppTypography.labelMd.copyWith(
                                color: AppColors.onSurfaceVariant,
                              ),
                            ),
                          ),
                      ],
                    ),
        ),
      ),
    );
  }
}

class _GiftSkeleton extends StatelessWidget {
  const _GiftSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        Spacer(flex: 2),
        SkeletonBox(width: 56, height: 56, borderRadius: 28),
        SizedBox(height: AppSpacing.lg),
        SkeletonBox(width: 260, height: 32, borderRadius: 8),
        SizedBox(height: AppSpacing.sm),
        SkeletonBox(width: 140, height: 20, borderRadius: 6),
        Spacer(flex: 3),
        SkeletonBox(width: double.infinity, height: 52, borderRadius: 16),
      ],
    );
  }
}

class _GiftError extends StatelessWidget {
  const _GiftError({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('Could not open this gift.', style: AppTypography.headlineMd),
        const SizedBox(height: AppSpacing.lg),
        PrimaryButton(label: 'Close', onPressed: onClose),
      ],
    );
  }
}
