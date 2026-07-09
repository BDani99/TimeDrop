import 'package:flutter/material.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';

/// Summary row for a sent capsule: share code + a friendly relative "opens"
/// string. Uses `memoryCardDecoration()` from `app_theme.dart` for the
/// shared "Memory Card" ambient-glow container look.
class MemoryCard extends StatelessWidget {
  const MemoryCard({
    super.key,
    required this.shareCode,
    required this.unlockTime,
    this.status = 'ready',
  });

  final String shareCode;
  final DateTime unlockTime;
  final String status;

  String get _relativeText {
    if (status == 'pending') return 'Uploading…';
    if (status == 'failed') return 'Upload failed';
    final now = DateTime.now();
    if (!unlockTime.isAfter(now)) return 'Ready to open';
    final diff = unlockTime.difference(now);
    if (diff.inDays >= 1) {
      return 'Opens in ${diff.inDays} day${diff.inDays == 1 ? '' : 's'}';
    }
    if (diff.inHours >= 1) {
      return 'Opens in ${diff.inHours} hour${diff.inHours == 1 ? '' : 's'}';
    }
    final minutes = diff.inMinutes < 1 ? 1 : diff.inMinutes;
    return 'Opens in $minutes minute${minutes == 1 ? '' : 's'}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: memoryCardDecoration(),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            shareCode,
            style: AppTypography.labelMd.copyWith(fontFamily: 'monospace'),
          ),
          Text(_relativeText, style: AppTypography.labelSm),
        ],
      ),
    );
  }
}
