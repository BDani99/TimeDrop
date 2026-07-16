import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/distance_motivation.dart';

/// Sci-fi radar view — no street map, pulsing rings + bearing indicator.
class SciFiRadarView extends StatefulWidget {
  const SciFiRadarView({
    super.key,
    required this.bearingDegrees,
    required this.distanceMeters,
    this.proximity = 0,
  });

  /// Bearing from device to target in degrees (0 = north).
  final double? bearingDegrees;
  final double? distanceMeters;

  /// 0..1 proximity factor for visual intensity.
  final double proximity;

  @override
  State<SciFiRadarView> createState() => _SciFiRadarViewState();
}

class _SciFiRadarViewState extends State<SciFiRadarView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: Duration(
        milliseconds: (1800 - (widget.proximity * 800).round()).clamp(500, 1800),
      ),
    )..repeat();
  }

  @override
  void didUpdateWidget(covariant SciFiRadarView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final ms = 1800 - (widget.proximity * 800).round();
    _pulse.duration = Duration(milliseconds: ms.clamp(500, 1800));
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final distance = widget.distanceMeters;
    return AspectRatio(
      aspectRatio: 1,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(
          alignment: Alignment.center,
          children: [
            AnimatedBuilder(
              animation: _pulse,
              builder: (context, _) {
                return CustomPaint(
                  painter: _SciFiRadarPainter(
                    pulse: _pulse.value,
                    bearingRadians: widget.bearingDegrees != null
                        ? widget.bearingDegrees! * pi / 180
                        : null,
                    proximity: widget.proximity,
                  ),
                  size: Size.infinite,
                );
              },
            ),
            if (distance != null)
              Positioned(
                bottom: 20,
                child: Column(
                  children: [
                    Text(
                      DistanceMotivation.formatDistance(distance),
                      style: AppTypography.headlineMd.copyWith(
                        color: AppColors.onPrimaryFixed,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      DistanceMotivation.messageFor(distance),
                      textAlign: TextAlign.center,
                      style: AppTypography.labelSm.copyWith(
                        color: AppColors.primaryFixedDim,
                      ),
                    ),
                  ],
                ),
              )
                  .animate()
                  .fadeIn(duration: 400.ms),
          ],
        ),
      ),
    );
  }
}

class _SciFiRadarPainter extends CustomPainter {
  _SciFiRadarPainter({
    required this.pulse,
    this.bearingRadians,
    required this.proximity,
  });

  final double pulse;
  final double? bearingRadians;
  final double proximity;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxR = size.width * 0.45;

    final bg = Paint()
      ..shader = RadialGradient(
        colors: [
          Color.lerp(AppColors.surfaceDim, AppColors.primaryFixedDim, proximity)!
              .withValues(alpha: 0.95),
          AppColors.inverseSurface.withValues(alpha: 0.98),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bg);

    for (var i = 3; i >= 1; i--) {
      final ringPaint = Paint()
        ..color = AppColors.primaryFixed.withValues(alpha: 0.08 + i * 0.04)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawCircle(center, maxR * i / 3, ringPaint);
    }

    final sweepPaint = Paint()
      ..shader = SweepGradient(
        colors: [
          Colors.transparent,
          AppColors.primaryFixed.withValues(alpha: 0.16 + proximity * 0.24),
          Colors.transparent,
        ],
        stops: const [0, 0.1, 0.2],
      ).createShader(Rect.fromCircle(center: center, radius: maxR))
      ..style = PaintingStyle.fill;
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(pulse * 2 * pi);
    canvas.translate(-center.dx, -center.dy);
    canvas.drawCircle(center, maxR, sweepPaint);
    canvas.restore();

    for (var i = 0; i < 3; i++) {
      final p = (pulse + i * 0.33) % 1.0;
      final ring = Paint()
        ..color = AppColors.primary.withValues(alpha: (1 - p) * 0.22)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawCircle(center, maxR * p, ring);
    }

    if (bearingRadians != null) {
      final needle = Paint()
        ..color = AppColors.primaryFixed
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;
      final tip = center +
          Offset(
            sin(bearingRadians!) * maxR * 0.75,
            -cos(bearingRadians!) * maxR * 0.75,
          );
      canvas.drawLine(center, tip, needle);
      canvas.drawCircle(
        tip,
        6,
        Paint()..color = AppColors.primaryFixed,
      );
    }

    canvas.drawCircle(
      center,
      10 + proximity * 6,
      Paint()..color = AppColors.primaryFixed,
    );
  }

  @override
  bool shouldRepaint(covariant _SciFiRadarPainter oldDelegate) =>
      oldDelegate.pulse != pulse ||
      oldDelegate.bearingRadians != bearingRadians ||
      oldDelegate.proximity != proximity;
}
