import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';

/// Timestamp + optional GPS coordinates rendered in the exact same style as
/// the live camera watermark. Used both during recording (`camera_screen`)
/// and when playing the resulting video back (`video_player_screen`), so the
/// recipient sees the same stamp in the corner of the final memory.
class WatermarkStamp extends StatelessWidget {
  const WatermarkStamp({
    super.key,
    required this.timestamp,
    this.latitude,
    this.longitude,
  });

  final DateTime timestamp;
  final double? latitude;
  final double? longitude;

  static const _months = [
    'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
    'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
  ];

  String _formatDate(DateTime d) =>
      '${_months[d.month - 1]} ${d.day}, ${d.year}';

  @override
  Widget build(BuildContext context) {
    final coords = (latitude != null && longitude != null)
        ? '${latitude!.toStringAsFixed(5)}, ${longitude!.toStringAsFixed(5)}'
        : null;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(width: 3, height: 34, color: AppColors.primary),
        const SizedBox(width: AppSpacing.sm),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _formatDate(timestamp),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
                shadows: [Shadow(color: Colors.black54, blurRadius: 6)],
              ),
            ),
            if (coords != null)
              Text(
                coords,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontFeatures: [FontFeature.tabularFigures()],
                  shadows: [Shadow(color: Colors.black54, blurRadius: 6)],
                ),
              ),
          ],
        ),
      ],
    );
  }
}
