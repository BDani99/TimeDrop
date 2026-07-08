import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';

/// Radar screen's blurred-map + pulsing-ring visual. Self-sized to a square
/// via [AspectRatio] so callers can drop it anywhere without worrying about
/// `flutter_map`'s bounded-constraints requirement.
class RadarView extends StatelessWidget {
  const RadarView({
    super.key,
    required this.center,
    required this.radiusMeters,
    required this.distanceMeters,
  });

  final LatLng center;
  final double radiusMeters;
  final double? distanceMeters;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          alignment: Alignment.center,
          children: [
            FlutterMap(
              options: MapOptions(
                initialCenter: center,
                initialZoom: 16,
                interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.timedrop.app',
                ),
                CircleLayer(
                  circles: [
                    CircleMarker(
                      point: center,
                      radius: radiusMeters,
                      useRadiusInMeter: true,
                      color: AppColors.primary.withValues(alpha: 0.15),
                      borderColor: AppColors.primary.withValues(alpha: 0.4),
                      borderStrokeWidth: 2,
                    ),
                  ],
                ),
              ],
            ),
            BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: Container(color: AppColors.surface.withValues(alpha: 0.15)),
            ),
            const _PulsingRing(),
            if (distanceMeters != null)
              Positioned(
                bottom: 20,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: const [
                      BoxShadow(color: Color(0x14000000), blurRadius: 12, offset: Offset(0, 4)),
                    ],
                  ),
                  child: Text(
                    '${distanceMeters!.round()}m away',
                    style: AppTypography.labelMd,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Simple looping concentric-ring pulse centered on the radar view.
class _PulsingRing extends StatefulWidget {
  const _PulsingRing();

  @override
  State<_PulsingRing> createState() => _PulsingRingState();
}

class _PulsingRingState extends State<_PulsingRing> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
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
        return Stack(
          alignment: Alignment.center,
          children: [
            Opacity(
              opacity: (1 - t).clamp(0.0, 1.0),
              child: Container(
                width: 40 + t * 120,
                height: 40 + t * 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.primary, width: 2),
                ),
              ),
            ),
            Container(
              width: 22,
              height: 22,
              decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.primary),
            ),
          ],
        );
      },
    );
  }
}
