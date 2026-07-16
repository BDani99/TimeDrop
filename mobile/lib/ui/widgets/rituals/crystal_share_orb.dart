import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../radar/particle_system.dart';

/// Floating crystal orb displaying the share code.
class CrystalShareOrb extends StatefulWidget {
  const CrystalShareOrb({super.key, required this.shareId});

  final String shareId;

  @override
  State<CrystalShareOrb> createState() => _CrystalShareOrbState();
}

class _CrystalShareOrbState extends State<CrystalShareOrb>
    with SingleTickerProviderStateMixin {
  late final AnimationController _floatController;

  @override
  void initState() {
    super.initState();
    _floatController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _floatController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _floatController,
      builder: (context, child) {
        final offset = sin(_floatController.value * pi * 2) * 5;
        return Transform.translate(
          offset: Offset(0, offset),
          child: child,
        );
      },
      child: SizedBox(
        width: 220,
        height: 260,
        child: Stack(
          alignment: Alignment.center,
          children: [
            const ParticleSystem(
              particleCount: 16,
              color: Color(0x4DFFB4A3),
              duration: Duration(seconds: 3),
            ),
            CustomPaint(
              painter: _CrystalPainter(),
              size: const Size(180, 200),
            )
                .animate(onPlay: (c) => c.repeat(reverse: true))
                .scale(
                  begin: const Offset(0.99, 0.99),
                  end: const Offset(1.01, 1.01),
                  duration: 3000.ms,
                  curve: Curves.easeInOut,
                ),
            Text(
              widget.shareId,
              style: AppTypography.headlineMd.copyWith(
                fontFamily: 'monospace',
                letterSpacing: 4,
                color: AppColors.onPrimaryFixed,
                shadows: const [
                  Shadow(color: Color(0x80A33D25), blurRadius: 12),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CrystalPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final path = Path();
    const sides = 6;
    final radius = size.width * 0.42;
    for (var i = 0; i < sides; i++) {
      final angle = (i * 2 * pi / sides) - pi / 2;
      final point = center + Offset(cos(angle) * radius, sin(angle) * radius);
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();

    final fill = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          AppColors.primary.withValues(alpha: 0.85),
          AppColors.secondaryContainer.withValues(alpha: 0.9),
          AppColors.primaryFixed.withValues(alpha: 0.75),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(path, fill);

    final glow = Paint()
      ..color = AppColors.primaryFixed.withValues(alpha: 0.25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 22);
    canvas.drawPath(path, glow);

    final stroke = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
