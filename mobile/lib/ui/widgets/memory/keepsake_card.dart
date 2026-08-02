import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';

/// The sand-coloured backdrop of the unlock ritual and the keepsake card.
///
/// One definition, because the card has to look identical on the day it is
/// earned and on every replay years later — and because it was previously
/// written out by hand in the unlock screen while the keepsake page inherited
/// the player's black, which made the same card render two different ways.
const Color kKeepsakeBackground = Color(0xFFF1E5D8);

/// The facts of a received memory — where it was left, when it was recorded,
/// how long it had been waiting, and how close the recipient was standing when
/// it opened.
///
/// These are the same lines the black intro walks through one at a time during
/// the unlock; here they arrive together, under the broken capsule. The class
/// exists so the unlock sequence and the keepsake page in the player render
/// from one definition — a card that looked different on the replay than at
/// the moment it was earned would not be the same keepsake.
class MemoryFacts {
  const MemoryFacts({
    this.capturedAt,
    this.fromName,
    this.placeLabel,
    this.distanceMeters,
  });

  final DateTime? capturedAt;
  final String? fromName;
  final String? placeLabel;

  /// How far away the recipient was at unlock. Null on replays of memories
  /// opened before this was recorded.
  final double? distanceMeters;

  static const _monthsShort = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  static const _monthsLong = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  String? get shortDate {
    final dt = capturedAt?.toLocal();
    if (dt == null) return null;
    return '${_monthsShort[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  String? get longDate {
    final dt = capturedAt?.toLocal();
    if (dt == null) return null;
    return '${_monthsLong[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  /// "3 months ago" — the line that carries the weight of the whole thing.
  ///
  /// Deliberately measured against *now*, not against the unlock: on a replay
  /// two years later it should say two years, because that is the truth the
  /// card is there to tell.
  String? get relativeLabel {
    final dt = capturedAt;
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

  String? get distanceLabel {
    final m = distanceMeters;
    if (m == null) return null;
    if (m < 1000) return '${m.round()} m away';
    return '${(m / 1000).toStringAsFixed(1)} km away';
  }

  String? get place {
    final value = placeLabel?.trim();
    return (value == null || value.isEmpty) ? null : value;
  }

  String? get sender {
    final value = fromName?.trim();
    return (value == null || value.isEmpty) ? null : value;
  }
}

/// The block of fact lines shown under the capsule. Static — the unlock
/// sequence fades the whole thing in as one, and the keepsake page shows it
/// outright.
///
/// Only one palette, deliberately: both places that draw it sit on
/// [kKeepsakeBackground], and a second colour scheme is how the two copies
/// drifted apart in the first place.
class MemoryFactsBlock extends StatelessWidget {
  const MemoryFactsBlock({super.key, required this.facts});

  final MemoryFacts facts;

  @override
  Widget build(BuildContext context) {
    const muted = AppColors.onSurfaceVariant;
    const strong = AppColors.primary;
    final sender = facts.sender;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          "It's yours.",
          textAlign: TextAlign.center,
          style: AppTypography.headlineLg.copyWith(color: strong),
        ),
        const SizedBox(height: AppSpacing.md),
        if (facts.place case final value?)
          _FactLine(icon: Icons.place_outlined, text: value, color: muted),
        if (facts.shortDate case final value?)
          _FactLine(icon: Icons.schedule_outlined, text: value, color: muted),
        if (facts.relativeLabel case final value?)
          _FactLine(icon: Icons.history_outlined, text: value, color: muted),
        if (facts.distanceLabel case final value?)
          _FactLine(icon: Icons.near_me_outlined, text: value, color: muted),
        if (sender != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            'from $sender',
            textAlign: TextAlign.center,
            style: AppTypography.bodyMd.copyWith(color: muted),
          ),
        ],
      ],
    );
  }
}

class _FactLine extends StatelessWidget {
  const _FactLine({
    required this.icon,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: AppTypography.labelMd.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

/// The broken capsule with the facts beneath it — the card the recipient earns
/// by going there, kept with the memory and reachable forever after by swiping
/// past the video and the photos.
///
/// Rendered in its finished state, on the same sand background it appeared on
/// during the unlock: the animation belongs to that moment and happens once,
/// but the picture it left behind should not change afterwards.
class KeepsakeCard extends StatelessWidget {
  const KeepsakeCard({super.key, required this.facts});

  final MemoryFacts facts;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: kKeepsakeBackground,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.xl,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CustomPaint(
              painter: CapsuleCrackPainter(crackProgress: 1),
              size: Size(120, 156),
            ),
            const SizedBox(height: AppSpacing.xl),
            MemoryFactsBlock(facts: facts),
          ],
        ),
      ),
    );
  }
}

/// Elongated pill-shaped time capsule with a golden crack that grows as
/// [crackProgress] runs from 0 → 1.
class CapsuleCrackPainter extends CustomPainter {
  const CapsuleCrackPainter({required this.crackProgress});

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
  bool shouldRepaint(covariant CapsuleCrackPainter oldDelegate) =>
      oldDelegate.crackProgress != crackProgress;
}
