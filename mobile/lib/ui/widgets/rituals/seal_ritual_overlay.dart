import 'dart:math';

import 'package:flutter/material.dart';

import '../../../core/haptics/app_haptics.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';

/// 2-second seal ritual overlay before capsule creation proceeds.
class SealRitualOverlay extends StatefulWidget {
  const SealRitualOverlay({
    super.key,
    this.previewImage,
    required this.onComplete,
  });

  final ImageProvider? previewImage;
  final VoidCallback onComplete;

  static Future<void> show(
    BuildContext context, {
    ImageProvider? previewImage,
  }) {
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black,
      pageBuilder: (ctx, _, _) => SealRitualOverlay(
        previewImage: previewImage,
        onComplete: () => Navigator.of(ctx).pop(),
      ),
    );
  }

  @override
  State<SealRitualOverlay> createState() => _SealRitualOverlayState();
}

class _SealRitualOverlayState extends State<SealRitualOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _hapticFired = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..forward().whenComplete(widget.onComplete);
    _controller.addListener(() {
      if (!_hapticFired && _controller.value >= 0.7) {
        _hapticFired = true;
        AppHaptics.heavy();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        final darken = Curves.easeInOut.transform((t / 0.25).clamp(0.0, 1.0));
        // The cover photo does not merely get smaller — it is drawn all the
        // way down into the seal, and is gone by the moment the lock shuts.
        // Ending at half size (as it used to) left the picture sitting behind
        // the lock, so nothing ever looked closed.
        final shrink = t >= 0.2
            ? Curves.easeInCubic.transform(((t - 0.2) / 0.52).clamp(0.0, 1.0))
            : 0.0;
        final goldSweep = t >= 0.45
            ? Curves.easeInOut.transform(((t - 0.45) / 0.28).clamp(0.0, 1.0))
            : 0.0;
        final lockClose = t >= 0.72
            ? Curves.easeOutCubic.transform(((t - 0.72) / 0.16).clamp(0.0, 1.0))
            : 0.0;
        final showText = t >= 0.9;

        return Material(
          color: Colors.black.withValues(alpha: darken),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 260,
                  height: 260,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      if (widget.previewImage != null && shrink < 1)
                        Opacity(
                          // Holds full strength through most of the descent,
                          // then dissolves over the final stretch.
                          opacity: (1.0 - shrink * 1.35).clamp(0.0, 1.0),
                          child: Transform.scale(
                            scale: 1.0 - shrink * 0.92,
                            child: Transform.rotate(
                              angle: shrink * 0.18,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(24),
                                child: Image(
                                  image: widget.previewImage!,
                                  width: 180,
                                  height: 220,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                          ),
                        ),
                      CustomPaint(
                        painter: _GoldSweepPainter(progress: goldSweep),
                        size: const Size(260, 260),
                      ),
                      CustomPaint(
                        painter: _LockPainter(progress: lockClose),
                        size: const Size(80, 80),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                Opacity(
                  opacity: showText ? ((t - 0.9) / 0.1).clamp(0.0, 1.0) : 0,
                  child: Text(
                    'Memory sealed.',
                    textAlign: TextAlign.center,
                    style: AppTypography.headlineLg.copyWith(
                      color: AppColors.ritualGold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _GoldSweepPainter extends CustomPainter {
  _GoldSweepPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final center = Offset(size.width / 2, size.height / 2);
    final rect = Rect.fromCircle(center: center, radius: size.width / 2);
    final paint = Paint()
      ..shader = SweepGradient(
        startAngle: -pi / 2,
        endAngle: 3 * pi / 2,
        colors: [
          Colors.transparent,
          AppColors.ritualGold.withValues(alpha: 0.85),
          Colors.transparent,
        ],
        stops: [0, progress.clamp(0.01, 1.0), 1],
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    canvas.drawArc(rect, -pi / 2, pi * 2 * progress, false, paint);
  }

  @override
  bool shouldRepaint(covariant _GoldSweepPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class _LockPainter extends CustomPainter {
  _LockPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final bodyPaint = Paint()
      ..color = AppColors.ritualGold
      ..style = PaintingStyle.fill;
    final shacklePaint = Paint()
      ..color = AppColors.ritualGold
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;

    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(size.width * 0.2, size.height * 0.45, size.width * 0.6, size.height * 0.4),
      const Radius.circular(8),
    );
    canvas.drawRRect(body, bodyPaint);

    final shackleOpen = (1 - progress) * 20;
    final path = Path()
      ..moveTo(size.width * 0.35, size.height * 0.45)
      ..arcToPoint(
        Offset(size.width * 0.65, size.height * 0.45),
        radius: Radius.circular(size.width * 0.15 + shackleOpen),
        clockwise: false,
      );
    canvas.drawPath(path, shacklePaint);
  }

  @override
  bool shouldRepaint(covariant _LockPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
