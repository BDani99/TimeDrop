import 'dart:math';

import 'package:flutter/material.dart';

/// Lightweight particle burst for unlock / crystal effects.
class ParticleSystem extends StatefulWidget {
  const ParticleSystem({
    super.key,
    this.particleCount = 24,
    this.color = const Color(0xFFE3B778),
    this.duration = const Duration(milliseconds: 1600),
  });

  final int particleCount;
  final Color color;
  final Duration duration;

  @override
  State<ParticleSystem> createState() => _ParticleSystemState();
}

class _ParticleSystemState extends State<ParticleSystem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<_Particle> _particles;
  final _random = Random();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..forward();
    _particles = List.generate(widget.particleCount, (_) {
      final angle = _random.nextDouble() * pi * 2;
      final speed = 30 + _random.nextDouble() * 90;
      return _Particle(
        angle: angle,
        speed: speed,
        size: 1.5 + _random.nextDouble() * 3,
        opacity: 0.3 + _random.nextDouble() * 0.5,
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Fills whatever slot it's given (Positioned.fill / SizedBox.expand).
    // Without `SizedBox.expand`, `CustomPaint(size: Size.infinite)` in loose
    // constraints (e.g. an unpositioned Stack child) collapses to zero and
    // the particles all spawn from (0, 0) — the "top-left burst" bug.
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return SizedBox.expand(
          child: CustomPaint(
            painter: _ParticlePainter(
              progress: _controller.value,
              particles: _particles,
              color: widget.color,
            ),
          ),
        );
      },
    );
  }
}

class _Particle {
  _Particle({
    required this.angle,
    required this.speed,
    required this.size,
    required this.opacity,
  });

  final double angle;
  final double speed;
  final double size;
  final double opacity;
}

class _ParticlePainter extends CustomPainter {
  _ParticlePainter({
    required this.progress,
    required this.particles,
    required this.color,
  });

  final double progress;
  final List<_Particle> particles;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final eased = Curves.easeOutCubic.transform(progress);
    final fade = Curves.easeInCubic.transform(1 - progress);
    for (final p in particles) {
      final dist = p.speed * eased;
      final dx = cos(p.angle) * dist;
      final dy = sin(p.angle) * dist;
      final paint = Paint()
        ..color = color.withValues(alpha: p.opacity * fade)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(center + Offset(dx, dy), p.size, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ParticlePainter oldDelegate) =>
      oldDelegate.progress != progress;
}
