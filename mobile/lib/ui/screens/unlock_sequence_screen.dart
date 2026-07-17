import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/haptics/app_haptics.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../widgets/radar/particle_system.dart';
import 'video_player_screen.dart';

/// Unlock ritual sequence before video playback (skipped on vault replay).
/// ~6.5s cream-background ceremony: intro → capsule → meta → crack → burst → close.
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
    this.fromName,
    this.placeLabel,
    this.distanceMeters,
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
  final String? fromName;
  final String? placeLabel;
  final double? distanceMeters;

  @override
  State<UnlockSequenceScreen> createState() => _UnlockSequenceScreenState();
}

class _UnlockSequenceScreenState extends State<UnlockSequenceScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _hapticFired = false;

  // Timeline on a 6500 ms controller (t = 0 → 1).
  static const _introEnd = 0.14;
  static const _capsuleStart = 0.10;
  static const _capsuleEnd = 0.32;
  static const _meta1Start = 0.28;
  static const _meta1End = 0.40;
  static const _meta2Start = 0.38;
  static const _meta2End = 0.50;
  static const _meta3Start = 0.48;
  static const _meta3End = 0.58;
  static const _crackStart = 0.55;
  static const _crackEnd = 0.72;
  static const _burstStart = 0.70;
  static const _closeStart = 0.80;
  static const _fadeOutStart = 0.92;

  static const _bg = Color(0xFFF1E5D8);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 6500),
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
      PageRouteBuilder(
        pageBuilder: (_, _, _) => VideoPlayerScreen(
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
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
        transitionDuration: const Duration(milliseconds: 500),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _phase(double t, double start, double end, {Curve curve = Curves.easeOutCubic}) {
    if (t <= start) return 0;
    if (t >= end) return 1;
    return curve.transform(((t - start) / (end - start)).clamp(0.0, 1.0));
  }

  String? _dateLabel() {
    final dt = widget.capturedAt;
    if (dt == null) return null;
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  String? _distanceLabel() {
    final m = widget.distanceMeters;
    if (m == null) return null;
    if (m < 1000) return '${m.round()} m away';
    return '${(m / 1000).toStringAsFixed(1)} km away';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = _controller.value;
          final intro = _phase(t, 0, _introEnd);
          final capsuleIn = _phase(t, _capsuleStart, _capsuleEnd);
          final float = math.sin(t * math.pi * 2.2) * 6 * capsuleIn;
          final crack = _phase(t, _crackStart, _crackEnd, curve: Curves.easeInOut);
          final burst = t >= _burstStart && t < _fadeOutStart;
          final close = _phase(t, _closeStart, 0.90);
          final fadeOut = _phase(t, _fadeOutStart, 1.0, curve: Curves.easeIn);

          final meta1 = _phase(t, _meta1Start, _meta1End);
          final meta2 = _phase(t, _meta2Start, _meta2End);
          final meta3 = _phase(t, _meta3Start, _meta3End);

          final from = widget.fromName?.trim();
          final place = widget.placeLabel?.trim();
          final date = _dateLabel();
          final dist = _distanceLabel();

          return Opacity(
            opacity: 1.0 - fadeOut * 0.85,
            child: Stack(
              fit: StackFit.expand,
              alignment: Alignment.center,
              children: [
                if (burst)
                  const Positioned.fill(
                    child: IgnorePointer(
                      child: ParticleSystem(
                        particleCount: 18,
                        color: AppColors.ritualGold,
                      ),
                    ),
                  ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                    child: Column(
                      children: [
                        const Spacer(flex: 2),
                        Opacity(
                          opacity: intro,
                          child: Column(
                            children: [
                              Text(
                                'A memory found you',
                                textAlign: TextAlign.center,
                                style: AppTypography.headlineLg.copyWith(
                                  color: AppColors.onSurface,
                                ),
                              ),
                              if (from != null && from.isNotEmpty) ...[
                                const SizedBox(height: AppSpacing.sm),
                                Text(
                                  'from $from',
                                  textAlign: TextAlign.center,
                                  style: AppTypography.bodyMd.copyWith(
                                    color: AppColors.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xl),
                        Opacity(
                          opacity: capsuleIn,
                          child: Transform.translate(
                            offset: Offset(0, float - 12 * crack),
                            child: CustomPaint(
                              painter: _CapsuleCrackPainter(crackProgress: crack),
                              size: const Size(120, 156),
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xl),
                        SizedBox(
                          height: 88,
                          child: Column(
                            children: [
                              if (place != null && place.isNotEmpty)
                                _MetaLine(opacity: meta1, text: place, icon: Icons.place_outlined),
                              if (date != null)
                                _MetaLine(opacity: meta2, text: date, icon: Icons.schedule_outlined),
                              if (dist != null)
                                _MetaLine(opacity: meta3, text: dist, icon: Icons.near_me_outlined),
                            ],
                          ),
                        ),
                        const Spacer(flex: 2),
                        Opacity(
                          opacity: close,
                          child: Text(
                            "It's yours.",
                            textAlign: TextAlign.center,
                            style: AppTypography.headlineLg.copyWith(
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                        const Spacer(flex: 1),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _MetaLine extends StatelessWidget {
  const _MetaLine({
    required this.opacity,
    required this.text,
    required this.icon,
  });

  final double opacity;
  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: AppColors.onSurfaceVariant),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                text,
                textAlign: TextAlign.center,
                style: AppTypography.labelMd.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Elongated pill-shaped time capsule with a golden crack that grows as
/// [crackProgress] runs from 0 → 1.
class _CapsuleCrackPainter extends CustomPainter {
  _CapsuleCrackPainter({required this.crackProgress});

  final double crackProgress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    final halo = Paint()
      ..shader = RadialGradient(
        colors: [
          AppColors.primary.withValues(alpha: 0.22),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: center, radius: size.width * 0.85))
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20);
    canvas.drawCircle(center, size.width * 0.55, halo);

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

    canvas.drawRRect(
      body,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.primary,
            AppColors.primaryContainer,
            AppColors.secondaryContainer,
          ],
        ).createShader(bodyRect),
    );

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
        ..lineTo(
          bodyRect.center.dx - bodyRect.width * 0.14 * crackProgress,
          bodyRect.top + bodyRect.height * 0.40,
        )
        ..lineTo(
          bodyRect.center.dx + bodyRect.width * 0.12 * crackProgress,
          bodyRect.top + bodyRect.height * 0.60,
        )
        ..lineTo(bodyRect.center.dx, bodyRect.bottom - bodyRect.height * 0.14);
      canvas.drawPath(path, crackPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _CapsuleCrackPainter oldDelegate) =>
      oldDelegate.crackProgress != crackProgress;
}
