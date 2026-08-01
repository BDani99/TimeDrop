import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/haptics/app_haptics.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../widgets/navigation/opaque_page_route.dart';
import '../widgets/radar/particle_system.dart';
import 'video_player_screen.dart';

/// The beats of the unlock sequence, in milliseconds on a single controller.
///
/// Public, and kept as plain numbers rather than fractions, because the order
/// of these values *is* the design: a constant that drifts past its neighbour
/// produces a sequence that plays out of order, which on a device looks like a
/// rendering bug rather than a typo. Asserted in `unlock_sequence_test.dart`.
class UnlockTimeline {
  const UnlockTimeline._();

  static const int totalMs = 7200;

  // 1 — black intro: "Recorded", the date and how long ago, all at once.
  static const int introInEndMs = 800;
  static const int introOutStartMs = 2400;
  static const int introOutEndMs = 3000;

  // 2 — the capsule, alone, cracking open. No text competes with it.
  static const int bgSwitchStartMs = 3000;
  static const int bgSwitchEndMs = 3200;
  static const int capsuleStartMs = 3000;
  static const int capsuleEndMs = 3600;
  static const int crackStartMs = 3600;
  static const int crackEndMs = 4900;
  static const int burstStartMs = 4700;

  // 3 — every line arrives together.
  static const int textStartMs = 5100;
  static const int textEndMs = 5800;

  // 4 — hand off to playback.
  static const int fadeOutStartMs = 6600;

  /// Position on the 0 → 1 controller.
  static double at(int ms) => ms / totalMs;

  static double get introInEnd => at(introInEndMs);
  static double get introOutStart => at(introOutStartMs);
  static double get introOutEnd => at(introOutEndMs);
  static double get bgSwitchStart => at(bgSwitchStartMs);
  static double get bgSwitchEnd => at(bgSwitchEndMs);
  static double get capsuleStart => at(capsuleStartMs);
  static double get capsuleEnd => at(capsuleEndMs);
  static double get crackStart => at(crackStartMs);
  static double get crackEnd => at(crackEndMs);
  static double get burstStart => at(burstStartMs);
  static double get textStart => at(textStartMs);
  static double get textEnd => at(textEndMs);
  static double get fadeOutStart => at(fadeOutStartMs);

  /// The beats in the order they must occur, for assertions.
  static const List<int> orderedBeats = [
    introInEndMs,
    introOutStartMs,
    introOutEndMs,
    capsuleEndMs,
    burstStartMs,
    crackEndMs,
    textStartMs,
    textEndMs,
    fadeOutStartMs,
    totalMs,
  ];
}

/// The unlock ritual, played once when a memory is found in the field (the
/// Vault's replay goes straight to the player).
///
/// It used to run ~14.6 s in two disconnected halves: a cream ceremony here,
/// then a separate black pre-roll inside the player. Both are now one
/// timeline, in the order the moment actually wants — see [UnlockTimeline]:
///
///   1. **Black** — "Recorded", the date and "3 months ago", all at once.
///   2. **The capsule cracks** — nothing else on screen, so the break is the
///      only thing to look at.
///   3. **Every line at once** — "It's yours." plus place, date and distance.
///   4. **Crossfade** into playback.
///
/// Total ~7.2 s. Half the old length, but each beat still gets room — the
/// reveal is the product, not an interstitial to sit through.
class UnlockSequenceScreen extends StatefulWidget {
  const UnlockSequenceScreen({
    super.key,
    required this.mediaBytes,
    required this.mimeType,
    this.note,
    this.photos = const [],
    this.capturedAt,
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

  static const _cream = Color(0xFFF1E5D8);

  static const _monthsShort = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  static const _monthsLong = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: UnlockTimeline.totalMs),
    )..forward().whenComplete(_goToPlayer);
    _controller.addListener(() {
      if (!_hapticFired && _controller.value >= UnlockTimeline.burstStart) {
        _hapticFired = true;
        AppHaptics.successBurst();
      }
    });
  }

  void _goToPlayer() {
    if (!mounted) return;
    // Opaque (no FadeTransition): Android video textures fail under opacity
    // animations and never attach — playback appears permanently stuck.
    Navigator.pushReplacement(
      context,
      OpaquePageRoute(
        page: VideoPlayerScreen(
          mediaBytes: widget.mediaBytes,
          mimeType: widget.mimeType,
          note: widget.note,
          photos: widget.photos,
          capturedAt: widget.capturedAt,
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

  double _phase(double t, double start, double end,
      {Curve curve = Curves.easeOutCubic}) {
    if (t <= start) return 0;
    if (t >= end) return 1;
    return curve.transform(((t - start) / (end - start)).clamp(0.0, 1.0));
  }

  String? _shortDate() {
    final dt = widget.capturedAt?.toLocal();
    if (dt == null) return null;
    return '${_monthsShort[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  String? _longDate() {
    final dt = widget.capturedAt?.toLocal();
    if (dt == null) return null;
    return '${_monthsLong[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  /// "3 months ago" — the line that does the emotional work in the intro.
  String? _relativeLabel() {
    final dt = widget.capturedAt;
    if (dt == null) return null;
    final diff = DateTime.now().difference(dt);
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
    return Scaffold(
      backgroundColor: Colors.black,
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = _controller.value;

          final introIn = _phase(t, 0, UnlockTimeline.introInEnd);
          final introOut = _phase(t, UnlockTimeline.introOutStart, UnlockTimeline.introOutEnd,
              curve: Curves.easeIn);
          final intro = introIn * (1 - introOut);

          // The switch to cream is deliberately fast — a slow crossfade here
          // reads as a loading state rather than a scene change.
          final bgSwitch = _phase(t, UnlockTimeline.bgSwitchStart, UnlockTimeline.bgSwitchEnd,
              curve: Curves.easeOut);
          // …and back toward black at the end, so the handoff to the player's
          // black background has nothing to flash against.
          final bgReturn = _phase(t, UnlockTimeline.fadeOutStart, 1.0, curve: Curves.easeIn);
          final background = Color.lerp(
            Color.lerp(Colors.black, _cream, bgSwitch)!,
            Colors.black,
            bgReturn,
          )!;

          final capsuleIn = _phase(t, UnlockTimeline.capsuleStart, UnlockTimeline.capsuleEnd);
          final crack =
              _phase(t, UnlockTimeline.crackStart, UnlockTimeline.crackEnd, curve: Curves.easeInOut);
          final burst = t >= UnlockTimeline.burstStart && t < UnlockTimeline.fadeOutStart;
          final float = math.sin(t * math.pi * 2.2) * 6 * capsuleIn;

          // Step 3: one opacity for every line, so they arrive together.
          final text = _phase(t, UnlockTimeline.textStart, UnlockTimeline.textEnd);
          final contentFade =
              1.0 - _phase(t, UnlockTimeline.fadeOutStart, 1.0, curve: Curves.easeIn);

          final from = widget.fromName?.trim();
          final place = widget.placeLabel?.trim();

          return ColoredBox(
            color: background,
            child: Stack(
              fit: StackFit.expand,
              alignment: Alignment.center,
              children: [
                if (burst)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Opacity(
                        opacity: contentFade,
                        child: const ParticleSystem(
                          particleCount: 18,
                          color: AppColors.ritualGold,
                        ),
                      ),
                    ),
                  ),

                // Step 1 — the black card. Kept in the stack (not swapped) so
                // it can fade out under the capsule fading in.
                if (intro > 0)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Opacity(
                        opacity: intro,
                        child: _IntroCard(
                          date: _longDate(),
                          relative: _relativeLabel(),
                          fromName: from,
                        ),
                      ),
                    ),
                  ),

                // Steps 2 and 3 — the capsule, then the lines beneath it.
                if (capsuleIn > 0)
                  Opacity(
                    opacity: contentFade,
                    child: SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.lg,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Opacity(
                              opacity: capsuleIn,
                              child: Transform.translate(
                                offset: Offset(0, float - 12 * crack),
                                child: Transform.scale(
                                  // A settle rather than a fly-in: the capsule
                                  // is already where it belongs.
                                  scale: 0.94 + 0.06 * capsuleIn,
                                  child: CustomPaint(
                                    painter: _CapsuleCrackPainter(
                                      crackProgress: crack,
                                    ),
                                    size: const Size(120, 156),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xl),
                            // Fixed height so the lines fading in never nudge
                            // the capsule off centre.
                            SizedBox(
                              height: 132,
                              child: Opacity(
                                opacity: text,
                                child: Column(
                                  children: [
                                    Text(
                                      "It's yours.",
                                      textAlign: TextAlign.center,
                                      style: AppTypography.headlineLg.copyWith(
                                        color: AppColors.primary,
                                      ),
                                    ),
                                    const SizedBox(height: AppSpacing.md),
                                    if (place != null && place.isNotEmpty)
                                      _MetaLine(
                                        text: place,
                                        icon: Icons.place_outlined,
                                      ),
                                    if (_shortDate() case final d?)
                                      _MetaLine(
                                        text: d,
                                        icon: Icons.schedule_outlined,
                                      ),
                                    if (_distanceLabel() case final d?)
                                      _MetaLine(
                                        text: d,
                                        icon: Icons.near_me_outlined,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
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

  String? _distanceLabel() {
    final m = widget.distanceMeters;
    if (m == null) return null;
    if (m < 1000) return '${m.round()} m away';
    return '${(m / 1000).toStringAsFixed(1)} km away';
  }
}

/// Step 1: black screen, every line at once. This replaces the old
/// `VideoPreRoll`, which staged the same three lines one after another over
/// 8.1 s inside the player.
class _IntroCard extends StatelessWidget {
  const _IntroCard({
    required this.date,
    required this.relative,
    required this.fromName,
  });

  final String? date;
  final String? relative;
  final String? fromName;

  @override
  Widget build(BuildContext context) {
    final from = fromName;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Recorded',
              textAlign: TextAlign.center,
              style: AppTypography.displayLg.copyWith(
                color: Colors.white,
                fontSize: 36,
              ),
            ),
            if (date != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                date!,
                textAlign: TextAlign.center,
                style: AppTypography.headlineLg.copyWith(color: Colors.white70),
              ),
            ],
            if (relative != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                relative!,
                textAlign: TextAlign.center,
                style: AppTypography.bodyLg.copyWith(color: Colors.white54),
              ),
            ],
            if (from != null && from.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.lg),
              Text(
                'from $from',
                textAlign: TextAlign.center,
                style: AppTypography.bodyMd.copyWith(color: Colors.white38),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.text, required this.icon});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
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
