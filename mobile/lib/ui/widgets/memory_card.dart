import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';

/// A sent-capsule card on the Home screen. Shows the drop location as its
/// title and a friendly unlock-time subtitle — the raw share code is kept only
/// for deep-link generation, never displayed. Upload lifecycle is expressed
/// visually: a thin progress bar along the bottom edge while uploading, and a
/// discreet red "tap to retry" state on failure. Uses `memoryCardDecoration()`
/// for the shared ambient-glow look.
class MemoryCard extends StatelessWidget {
  const MemoryCard({
    super.key,
    required this.unlockTime,
    this.city,
    this.status = 'ready',
    this.onRetry,
    this.accentColor,
  });

  /// Reverse-geocoded drop location shown as the title; falls back to a
  /// neutral label while unknown (e.g. still geocoding, or offline).
  final String? city;
  final DateTime unlockTime;
  final String status;

  /// Invoked when a `failed` card is tapped. Wired to
  /// `CapsuleProvider.retryUpload`. Null disables the tap.
  final VoidCallback? onRetry;

  /// Optional adaptive accent from cover/thumbnail palette extraction.
  final Color? accentColor;

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  bool get _isPending => status == 'pending';
  bool get _isFailed => status == 'failed';

  String get _title => (city != null && city!.trim().isNotEmpty)
      ? city!.trim()
      : 'A hidden place';

  String get _subtitle {
    if (_isFailed) return 'Upload Failed — Tap to Retry';
    if (_isPending) return 'Sealing your memory…';
    final now = DateTime.now();
    if (!unlockTime.isAfter(now)) return 'Ready to open';
    final diff = unlockTime.difference(now);
    // Far out: an exact countdown is noise — show the sealed-until month.
    if (diff.inDays >= 30) {
      return 'Sealed until ${_months[unlockTime.month - 1]} ${unlockTime.year}';
    }
    if (diff.inDays >= 1) {
      return 'Unlocks in ${diff.inDays} day${diff.inDays == 1 ? '' : 's'}';
    }
    if (diff.inHours >= 1) {
      return 'Unlocks in ${diff.inHours} hour${diff.inHours == 1 ? '' : 's'}';
    }
    final minutes = diff.inMinutes < 1 ? 1 : diff.inMinutes;
    return 'Unlocks in $minutes minute${minutes == 1 ? '' : 's'}';
  }

  IconData get _leadingIcon {
    if (_isFailed) return Icons.error_outline;
    if (_isPending) return Icons.hourglass_top;
    return Icons.place;
  }

  Color get _accent => _isFailed ? AppColors.error : (accentColor ?? AppColors.primary);

  @override
  Widget build(BuildContext context) {
    final card = Container(
      width: double.infinity,
      decoration: memoryCardDecoration(tint: _isFailed ? AppColors.error : accentColor),
      child: ClipRRect(
        borderRadius: AppRadii.lgRadius,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm + 2,
              ),
              child: Row(
                children: [
                  Icon(_leadingIcon, size: 20, color: _accent),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.labelMd.copyWith(
                            color: AppColors.onSurface,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.labelSm.copyWith(
                            color: _isFailed ? AppColors.error : AppColors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_isFailed) ...[
                    const SizedBox(width: AppSpacing.sm),
                    Icon(Icons.refresh, size: 18, color: AppColors.error),
                  ],
                ],
              ),
            ),
            // Thin indeterminate progress bar hugging the bottom edge while the
            // background upload is in flight (no real byte-progress available).
            if (_isPending)
              const Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: LinearProgressIndicator(
                  minHeight: 3,
                  backgroundColor: Colors.transparent,
                  valueColor: AlwaysStoppedAnimation(AppColors.primary),
                ),
              ),
          ],
        ),
      ),
    );

    if (_isFailed && onRetry != null) {
      return Semantics(
        button: true,
        label: 'Upload failed, tap to retry',
        child: InkWell(
          onTap: onRetry,
          borderRadius: AppRadii.lgRadius,
          child: card,
        ),
      );
    }
    return card;
  }
}
