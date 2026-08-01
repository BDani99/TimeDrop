import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/haptics/app_haptics.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radii.dart';

/// Wraps the Vault card of a memory the user has *just* opened in the field,
/// so arriving in the Vault says "here it is" instead of leaving them to find
/// it in a list.
///
/// One gold sweep around the card's edge, a slight swell, one soft haptic —
/// then it is an ordinary card forever after. The sweep is the same gesture
/// the seal ritual uses when a memory is buried, drawn on a rounded rectangle
/// instead of a circle so it traces this card rather than sitting on top of it.
class NewMemoryHighlight extends StatefulWidget {
  const NewMemoryHighlight({
    super.key,
    required this.child,
    required this.active,
  });

  final Widget child;

  /// False for every other card — the widget then costs nothing but a build.
  final bool active;

  @override
  State<NewMemoryHighlight> createState() => _NewMemoryHighlightState();
}

class _NewMemoryHighlightState extends State<NewMemoryHighlight>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void initState() {
    super.initState();
    if (widget.active) _start();
  }

  @override
  void didUpdateWidget(covariant NewMemoryHighlight oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) _start();
  }

  void _start() {
    if (_controller != null) return;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    // Let the list settle (and the scroll-to finish) before drawing attention
    // to a card that may still be moving.
    Future<void>.delayed(const Duration(milliseconds: 260), () {
      if (!mounted) return;
      AppHaptics.light();
      _controller?.forward();
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) return widget.child;

    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final t = controller.value;
        // Swell early, settle back — peaks at t = 0.3 and is gone by 0.75.
        final swell = math.sin((t.clamp(0.0, 0.75) / 0.75) * math.pi);
        final sweep = Curves.easeInOut.transform(t);
        // The trace fades out over the last quarter so the card is left clean.
        final sweepFade = 1.0 - Curves.easeIn.transform(
          ((t - 0.75) / 0.25).clamp(0.0, 1.0),
        );

        return Transform.scale(
          scale: 1 + 0.03 * swell,
          child: CustomPaint(
            foregroundPainter: _CardSweepPainter(
              progress: sweep,
              opacity: sweepFade,
            ),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

/// A gold arc travelling once around the card's rounded outline.
class _CardSweepPainter extends CustomPainter {
  _CardSweepPainter({required this.progress, required this.opacity});

  final double progress;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || opacity <= 0) return;

    final rect = Offset.zero & size;
    final rrect = AppRadii.lgRadius.toRRect(rect);
    final full = Path()..addRRect(rrect);

    // Cut the outline to the travelled fraction, so the highlight reads as a
    // stroke being drawn rather than a border switching on.
    final metrics = full.computeMetrics().toList();
    final total = metrics.fold<double>(0, (sum, m) => sum + m.length);
    var remaining = total * progress;

    final drawn = Path();
    for (final metric in metrics) {
      if (remaining <= 0) break;
      final take = math.min(remaining, metric.length);
      drawn.addPath(metric.extractPath(0, take), Offset.zero);
      remaining -= take;
    }

    canvas.drawPath(
      drawn,
      Paint()
        ..color = AppColors.ritualGold.withValues(alpha: 0.85 * opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2),
    );
  }

  @override
  bool shouldRepaint(covariant _CardSweepPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.opacity != opacity;
}
