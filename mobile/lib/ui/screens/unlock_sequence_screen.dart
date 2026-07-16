import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/haptics/app_haptics.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../widgets/radar/particle_system.dart';
import 'video_player_screen.dart';

/// Unlock ritual sequence before video playback (skipped on vault replay).
class UnlockSequenceScreen extends StatefulWidget {
  const UnlockSequenceScreen({
    super.key,
    required this.mediaBytes,
    required this.mimeType,
    this.note,
    this.photos = const [],
    this.capturedAt,
    this.skipPreRoll = false,
    this.capsuleId,
    this.latitude,
    this.longitude,
  });

  final Uint8List mediaBytes;
  final String mimeType;
  final String? note;
  final List<Uint8List> photos;
  final DateTime? capturedAt;
  final bool skipPreRoll;
  final String? capsuleId;
  final double? latitude;
  final double? longitude;

  @override
  State<UnlockSequenceScreen> createState() => _UnlockSequenceScreenState();
}

class _UnlockSequenceScreenState extends State<UnlockSequenceScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _hapticFired = false;

  // Named phase thresholds — makes the ritual timeline easy to reason about
  // and keeps every derived value in sync when we tweak pacing.
  static const _fadeInEnd = 0.15;
  static const _liftStart = 0.15;
  static const _liftEnd = 0.45;
  static const _crackStart = 0.4;
  static const _crackEnd = 0.62;
  static const _burstStart = 0.6;
  static const _textStart = 0.75;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..forward().whenComplete(_goToPlayer);
    _controller.addListener(() {
      if (!_hapticFired && _controller.value >= _burstStart) {
        _hapticFired = true;
        AppHaptics.successBurst();
      }
    });
  }

  void _goToPlayer() {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => VideoPlayerScreen(
          mediaBytes: widget.mediaBytes,
          mimeType: widget.mimeType,
          note: widget.note,
          photos: widget.photos,
          capturedAt: widget.capturedAt,
          skipPreRoll: widget.skipPreRoll,
          capsuleId: widget.capsuleId,
          latitude: widget.latitude,
          longitude: widget.longitude,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _phase(double t, double start, double end, {Curve curve = Curves.easeInOut}) {
    if (t <= start) return 0;
    if (t >= end) return 1;
    return curve.transform(((t - start) / (end - start)).clamp(0.0, 1.0));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = _controller.value;
          final fadeIn = _phase(t, 0, _fadeInEnd);
          final lift = _phase(t, _liftStart, _liftEnd, curve: Curves.easeOutCubic);
          final crack = _phase(t, _crackStart, _crackEnd);
          final burst = t >= _burstStart;
          final showText = t >= _textStart;

          return Stack(
            fit: StackFit.expand,
            alignment: Alignment.center,
            children: [
              // Full-screen particle burst — must be Positioned.fill so
              // Size.infinite inside actually gets a full-screen slot.
              if (burst)
                const Positioned.fill(
                  child: IgnorePointer(
                    child: ParticleSystem(
                      particleCount: 28,
                      color: AppColors.ritualGold,
                    ),
                  ),
                ),

              // Centered ritual scene: capsule illustration with a subtle
              // lift, plus the closing sentence directly beneath it. Using
              // a single centered column instead of ad-hoc `Padding(top: 200)`
              // guarantees stable placement on every screen size.
              Opacity(
                opacity: fadeIn,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Transform.translate(
                      offset: Offset(0, -32 * lift),
                      child: CustomPaint(
                        painter: _CapsuleCrackPainter(crackProgress: crack),
                        size: const Size(140, 180),
                      ),
                    ),
                    const SizedBox(height: 48),
                    AnimatedOpacity(
                      opacity: showText ? 1 : 0,
                      duration: const Duration(milliseconds: 700),
                      curve: Curves.easeOut,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 40),
                        child: Text(
                          'The memory is finally yours.',
                          textAlign: TextAlign.center,
                          style: AppTypography.headlineLg.copyWith(
                            color: AppColors.ritualGold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Elongated pill-shaped time capsule with a golden crack that grows as
/// [crackProgress] runs from 0 → 1. A soft radial halo behind the body and a
/// subtle inner highlight give it a warm, glass-like feel that reads even
/// against a black background.
class _CapsuleCrackPainter extends CustomPainter {
  _CapsuleCrackPainter({required this.crackProgress});

  final double crackProgress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    // Warm halo behind the capsule so it doesn't disappear on black.
    final halo = Paint()
      ..shader = RadialGradient(
        colors: [
          AppColors.primary.withValues(alpha: 0.35),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: center, radius: size.width * 0.75))
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 24);
    canvas.drawCircle(center, size.width * 0.6, halo);

    final bodyRect = Rect.fromLTWH(
      size.width * 0.22,
      size.height * 0.12,
      size.width * 0.56,
      size.height * 0.76,
    );
    final body = RRect.fromRectAndRadius(
      bodyRect,
      Radius.circular(size.width * 0.28),
    );

    // Body — warm vertical gradient from primary to secondaryContainer.
    canvas.drawRRect(
      body,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.primary,
            AppColors.primaryContainer,
            AppColors.secondaryContainer,
          ],
        ).createShader(bodyRect),
    );

    // Inner highlight on the left edge for a glass-like sheen.
    final sheenRect = Rect.fromLTWH(
      bodyRect.left + bodyRect.width * 0.08,
      bodyRect.top + bodyRect.height * 0.08,
      bodyRect.width * 0.22,
      bodyRect.height * 0.84,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(sheenRect, Radius.circular(sheenRect.width)),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.18)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );

    // Golden middle seam — always visible, brightens as the crack opens.
    final seamPaint = Paint()
      ..color = AppColors.ritualGold.withValues(alpha: 0.35 + crackProgress * 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawLine(
      Offset(bodyRect.center.dx, bodyRect.top + bodyRect.height * 0.18),
      Offset(bodyRect.center.dx, bodyRect.bottom - bodyRect.height * 0.18),
      seamPaint,
    );

    if (crackProgress > 0) {
      final crackPaint = Paint()
        ..color = AppColors.ritualGold.withValues(alpha: 0.6 + crackProgress * 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round;
      final path = Path()
        ..moveTo(bodyRect.center.dx, bodyRect.top + bodyRect.height * 0.16)
        ..lineTo(bodyRect.center.dx - bodyRect.width * 0.14 * crackProgress,
            bodyRect.top + bodyRect.height * 0.40)
        ..lineTo(bodyRect.center.dx + bodyRect.width * 0.12 * crackProgress,
            bodyRect.top + bodyRect.height * 0.60)
        ..lineTo(bodyRect.center.dx, bodyRect.bottom - bodyRect.height * 0.14);
      canvas.drawPath(path, crackPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _CapsuleCrackPainter oldDelegate) =>
      oldDelegate.crackProgress != crackProgress;
}
