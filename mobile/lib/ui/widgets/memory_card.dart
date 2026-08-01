import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';

/// A sent-capsule card on the Home screen. Shows the drop location as its
/// title and a sender-facing unlock-time subtitle. Upload lifecycle is
/// expressed visually: progress while sealing, retry on failure.
class MemoryCard extends StatelessWidget {
  const MemoryCard({
    super.key,
    required this.unlockTime,
    this.city,
    this.createdAt,
    this.status = 'ready',
    this.onRetry,
    this.onDiscard,
    this.onTap,
    this.accentColor,
  });

  final String? city;
  final DateTime unlockTime;
  final DateTime? createdAt;
  final String status;
  final VoidCallback? onRetry;

  /// Throws the drop away instead of retrying. Only surfaced on a failed
  /// upload, as a secondary icon next to the retry affordance.
  final VoidCallback? onDiscard;
  final VoidCallback? onTap;
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
    if (!unlockTime.isAfter(now)) return 'Unlockable for them';
    final diff = unlockTime.difference(now);
    if (diff.inDays >= 30) {
      return 'Sealed until ${_months[unlockTime.month - 1]} ${unlockTime.year}';
    }
    if (diff.inDays >= 1) {
      return 'Unlocks for them in ${diff.inDays} day${diff.inDays == 1 ? '' : 's'}';
    }
    if (diff.inHours >= 1) {
      return 'Unlocks for them in ${diff.inHours} hour${diff.inHours == 1 ? '' : 's'}';
    }
    final minutes = diff.inMinutes < 1 ? 1 : diff.inMinutes;
    return 'Unlocks for them in $minutes minute${minutes == 1 ? '' : 's'}';
  }

  String? get _dateLabel {
    final dt = createdAt;
    if (dt == null) return null;
    return '${_months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  IconData get _leadingIcon {
    if (_isFailed) return Icons.error_outline;
    if (_isPending) return Icons.hourglass_top;
    return Icons.place;
  }

  Color get _accent => _isFailed ? AppColors.error : (accentColor ?? AppColors.primary);

  @override
  Widget build(BuildContext context) {
    final date = _dateLabel;
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
                        if (date != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            date,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.labelSm.copyWith(
                              color: AppColors.onSurfaceVariant.withValues(alpha: 0.85),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (_isFailed) ...[
                    const Icon(Icons.refresh, size: 18, color: AppColors.error),
                    if (onDiscard != null)
                      Semantics(
                        button: true,
                        label: 'Discard this failed drop',
                        child: InkWell(
                          onTap: onDiscard,
                          customBorder: const CircleBorder(),
                          child: const Padding(
                            padding: EdgeInsets.all(AppSpacing.sm),
                            child: Icon(
                              Icons.close,
                              size: 18,
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                  ] else if (onTap != null)
                    const Icon(Icons.chevron_right, size: 20, color: AppColors.onSurfaceVariant),
                ],
              ),
            ),
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
    if (onTap != null) {
      return Semantics(
        button: true,
        label: 'Open sent memory details',
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadii.lgRadius,
          child: card,
        ),
      );
    }
    return card;
  }
}
