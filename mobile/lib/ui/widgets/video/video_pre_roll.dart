import 'package:animated_text_kit/animated_text_kit.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_typography.dart';

/// Pre-roll cinematic text before video playback starts.
class VideoPreRoll extends StatefulWidget {
  const VideoPreRoll({
    super.key,
    required this.capturedAt,
    required this.onComplete,
  });

  final DateTime capturedAt;
  final VoidCallback onComplete;

  @override
  State<VideoPreRoll> createState() => _VideoPreRollState();
}

class _VideoPreRollState extends State<VideoPreRoll> {
  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  String get _dateLabel {
    final d = widget.capturedAt.toLocal();
    return '${_months[d.month - 1]} ${d.day}, ${d.year}';
  }

  String get _relativeLabel {
    final diff = DateTime.now().difference(widget.capturedAt);
    if (diff.inDays >= 365) {
      final years = (diff.inDays / 365).floor();
      return '$years year${years == 1 ? '' : 's'} ago';
    }
    if (diff.inDays >= 30) {
      final months = (diff.inDays / 30).floor();
      return '$months month${months == 1 ? '' : 's'} ago';
    }
    if (diff.inDays >= 1) {
      return '${diff.inDays} day${diff.inDays == 1 ? '' : 's'} ago';
    }
    return 'Earlier today';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      child: DefaultTextStyle(
        style: AppTypography.headlineLg.copyWith(color: Colors.white70),
        textAlign: TextAlign.center,
        child: AnimatedTextKit(
          isRepeatingAnimation: false,
          totalRepeatCount: 1,
          onFinished: widget.onComplete,
          animatedTexts: [
            FadeAnimatedText(
              'Recorded',
              textStyle: AppTypography.displayLg.copyWith(
                color: Colors.white,
                fontSize: 36,
              ),
              duration: const Duration(milliseconds: 900),
            ),
            FadeAnimatedText(
              _dateLabel,
              textStyle: AppTypography.headlineLg.copyWith(color: Colors.white70),
              duration: const Duration(milliseconds: 900),
            ),
            FadeAnimatedText(
              _relativeLabel,
              textStyle: AppTypography.bodyLg.copyWith(color: Colors.white54),
              duration: const Duration(milliseconds: 900),
            ),
          ],
        ),
      ),
    );
  }
}
