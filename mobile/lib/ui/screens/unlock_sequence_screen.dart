import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/haptics/app_haptics.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../widgets/memory/keepsake_card.dart';
import '../widgets/navigation/opaque_page_route.dart';
import '../widgets/radar/particle_system.dart';
import 'video_player_screen.dart';

/// The beats of the unlock sequence, in milliseconds on a single controller.
///
/// Public, and kept as plain numbers rather than fractions, because the order
/// of these values *is* the design: a constant that drifts past its neighbour
/// produces a sequence that plays out of order, which on a device looks like a
/// rendering bug rather than a typo. Asserted in `recipient_flow_test.dart`.
class UnlockTimeline {
  const UnlockTimeline._();

  // ── 1. The black intro ──────────────────────────────────────────────────
  // Three lines, one after another, each fading up and away before the next
  // arrives. This is the original pre-roll's pacing, trimmed slightly: the
  // slow reveal of "Recorded → the date → how long ago" is what gives the
  // moment its weight, and compressing it into one card took that away.
  static const int lineMs = 1600;
  static const int linePauseMs = 500;
  static const int lineFadeMs = 420;
  static const int introHoldMs = 1000;

  static const int line1StartMs = 0;
  static const int line2StartMs = lineMs + linePauseMs; // 2100
  static const int line3StartMs = 2 * (lineMs + linePauseMs); // 4200
  static const int introEndMs = line3StartMs + lineMs + introHoldMs; // 6800

  // ── 2. The capsule, alone, cracking open ────────────────────────────────
  // Nothing is written on screen here. The break is the whole event.
  static const int bgSwitchStartMs = introEndMs; // 6800
  static const int bgSwitchEndMs = 7000;
  static const int capsuleStartMs = introEndMs; // 6800
  static const int capsuleEndMs = 7400;
  static const int crackStartMs = 7400;
  static const int crackEndMs = 8700;
  static const int burstStartMs = 8500;

  // ── 3. Every fact at once, under the broken capsule ─────────────────────
  static const int factsStartMs = 8900;
  static const int factsEndMs = 9700;

  // ── 4. Hand off to playback ─────────────────────────────────────────────
  static const int fadeOutStartMs = 10400;
  static const int totalMs = 11000;

  /// Position on the 0 → 1 controller.
  static double at(int ms) => ms / totalMs;

  static double get introEnd => at(introEndMs);
  static double get bgSwitchStart => at(bgSwitchStartMs);
  static double get bgSwitchEnd => at(bgSwitchEndMs);
  static double get capsuleStart => at(capsuleStartMs);
  static double get capsuleEnd => at(capsuleEndMs);
  static double get crackStart => at(crackStartMs);
  static double get crackEnd => at(crackEndMs);
  static double get burstStart => at(burstStartMs);
  static double get factsStart => at(factsStartMs);
  static double get factsEnd => at(factsEndMs);
  static double get fadeOutStart => at(fadeOutStartMs);

  /// Where each intro line starts, in order.
  static const List<int> lineStartsMs = [
    line1StartMs,
    line2StartMs,
    line3StartMs,
  ];

  /// The beats in the order they must occur, for assertions.
  static const List<int> orderedBeats = [
    line1StartMs,
    line2StartMs,
    line3StartMs,
    introEndMs,
    capsuleEndMs,
    burstStartMs,
    crackEndMs,
    factsStartMs,
    factsEndMs,
    fadeOutStartMs,
    totalMs,
  ];
}

/// The unlock ritual, played once when a memory is found in the field (the
/// Vault's replay goes straight to the player).
///
/// It used to run in two disconnected halves — a cream ceremony here, then a
/// separate black pre-roll inside the player, in that order. Both are now one
/// timeline, and the order is the one the moment wants:
///
///   1. **Black** — "Recorded", then the date, then "3 months ago", one at a
///      time, the way the pre-roll always told it.
///   2. **The capsule cracks** — nothing else on screen.
///   3. **Every fact at once** — where, when, how long ago, how close.
///   4. **Crossfade** into playback.
///
/// Step 3's card is not thrown away when the video starts: it is kept with the
/// memory and can be swiped back to at any time. See [KeepsakeCard].
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

  // Shared with the keepsake page, so the card the recipient keeps looks the
  // same as the one they were just given.
  static const _cream = kKeepsakeBackground;

  MemoryFacts get _facts => MemoryFacts(
        capturedAt: widget.capturedAt,
        fromName: widget.fromName,
        placeLabel: widget.placeLabel,
        distanceMeters: widget.distanceMeters,
      );

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
          facts: _facts,
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

  /// Opacity of intro line [index]: up, held, and away again inside its own
  /// slot. The last line does not fade out — it simply holds until the screen
  /// turns over to the capsule.
  double _lineOpacity(double t, int index) {
    final startMs = UnlockTimeline.lineStartsMs[index];
    final isLast = index == UnlockTimeline.lineStartsMs.length - 1;
    final fadeIn = _phase(
      t,
      UnlockTimeline.at(startMs),
      UnlockTimeline.at(startMs + UnlockTimeline.lineFadeMs),
    );
    final outStartMs = isLast
        ? UnlockTimeline.introEndMs - UnlockTimeline.lineFadeMs
        : startMs + UnlockTimeline.lineMs - UnlockTimeline.lineFadeMs;
    final fadeOut = _phase(
      t,
      UnlockTimeline.at(outStartMs),
      UnlockTimeline.at(outStartMs + UnlockTimeline.lineFadeMs),
      curve: Curves.easeIn,
    );
    return fadeIn * (1 - fadeOut);
  }

  @override
  Widget build(BuildContext context) {
    final facts = _facts;
    final lines = <_IntroLine>[
      _IntroLine(
        'Recorded',
        AppTypography.displayLg.copyWith(color: Colors.white, fontSize: 36),
      ),
      if (facts.longDate case final value?)
        _IntroLine(
          value,
          AppTypography.headlineLg.copyWith(color: Colors.white70),
        ),
      if (facts.relativeLabel case final value?)
        _IntroLine(
          value,
          AppTypography.bodyLg.copyWith(color: Colors.white54),
        ),
    ];

    return Scaffold(
      backgroundColor: Colors.black,
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = _controller.value;

          // The switch to cream is deliberately fast — a slow crossfade here
          // reads as a loading state rather than a scene change.
          final bgSwitch = _phase(t, UnlockTimeline.bgSwitchStart,
              UnlockTimeline.bgSwitchEnd,
              curve: Curves.easeOut);
          // …and back toward black at the end, so the handoff to the player's
          // black background has nothing to flash against.
          final bgReturn =
              _phase(t, UnlockTimeline.fadeOutStart, 1.0, curve: Curves.easeIn);
          final background = Color.lerp(
            Color.lerp(Colors.black, _cream, bgSwitch)!,
            Colors.black,
            bgReturn,
          )!;

          final capsuleIn =
              _phase(t, UnlockTimeline.capsuleStart, UnlockTimeline.capsuleEnd);
          final crack = _phase(
              t, UnlockTimeline.crackStart, UnlockTimeline.crackEnd,
              curve: Curves.easeInOut);
          final burst = t >= UnlockTimeline.burstStart &&
              t < UnlockTimeline.fadeOutStart;
          final float = math.sin(t * math.pi * 2.2) * 6 * capsuleIn;

          // One opacity for the whole block, so every fact arrives together.
          final factsIn =
              _phase(t, UnlockTimeline.factsStart, UnlockTimeline.factsEnd);
          final contentFade = 1.0 -
              _phase(t, UnlockTimeline.fadeOutStart, 1.0, curve: Curves.easeIn);

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

                // Step 1 — the lines, one at a time, each in the same place.
                if (t < UnlockTimeline.introEnd)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.lg,
                          ),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              for (var i = 0; i < lines.length; i++)
                                Opacity(
                                  opacity: _lineOpacity(t, i),
                                  child: Text(
                                    lines[i].text,
                                    textAlign: TextAlign.center,
                                    style: lines[i].style,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                // Steps 2 and 3 — the capsule, then the facts beneath it.
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
                                    painter: CapsuleCrackPainter(
                                      crackProgress: crack,
                                    ),
                                    size: const Size(120, 156),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xl),
                            // Fixed height so the facts fading in never nudge
                            // the capsule off centre.
                            SizedBox(
                              height: 190,
                              child: Opacity(
                                opacity: factsIn,
                                child: MemoryFactsBlock(facts: facts),
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
}

class _IntroLine {
  const _IntroLine(this.text, this.style);
  final String text;
  final TextStyle style;
}
