import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radii.dart';
import 'loading/skeleton_box.dart';

/// The recipient's overview map: where the memory is, where they are, and how
/// far apart those are.
///
/// This is the *macro* half of finding a drop. The radar is excellent at the
/// last fifty metres and useless at four kilometres — a compass needle is not
/// navigation. Here the user gets a real street map and can hand the
/// coordinates to their own maps app.
///
/// Follows the tile setup already used by the Vault map (Carto Voyager, retina
/// aware, generous buffers) so tiles are shared between the two screens rather
/// than fetched twice.
class RecipientMapView extends StatefulWidget {
  const RecipientMapView({
    super.key,
    required this.target,
    this.userLocation,
  });

  /// Where the memory is buried.
  final LatLng target;

  /// Where the recipient is, when known. Null before the first GPS fix.
  final LatLng? userLocation;

  @override
  State<RecipientMapView> createState() => _RecipientMapViewState();
}

class _RecipientMapViewState extends State<RecipientMapView> {
  final MapController _controller = MapController();
  bool _tilesLoaded = false;

  /// Recentres when the user moves far enough to matter. Following every
  /// metre would fight the user whenever they pan the map themselves.
  static const double _recentreThresholdMeters = 60;
  LatLng? _lastFittedUser;

  @override
  void didUpdateWidget(covariant RecipientMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final user = widget.userLocation;
    if (user == null) return;

    final last = _lastFittedUser;
    if (last != null) {
      final moved = const Distance().as(LengthUnit.Meter, last, user);
      if (moved < _recentreThresholdMeters) return;
    }
    _lastFittedUser = user;
    _fitBoth(user);
  }

  void _fitBoth(LatLng user) {
    // Guard: the controller throws if the map is not laid out yet.
    try {
      _controller.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds.fromPoints([widget.target, user]),
          padding: const EdgeInsets.all(56),
          maxZoom: 16,
        ),
      );
    } catch (_) {
      // Not mounted into the tree yet — the initial camera fit already covers
      // this case on the next build.
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.userLocation;
    final points = <LatLng>[widget.target, ?user];

    return ClipRRect(
      borderRadius: AppRadii.lgRadius,
      child: Stack(
        children: [
          Positioned.fill(
            child: ColoredBox(color: AppColors.surfaceContainer),
          ),
          FlutterMap(
            mapController: _controller,
            options: points.length == 1
                ? MapOptions(initialCenter: widget.target, initialZoom: 15)
                : MapOptions(
                    initialCameraFit: CameraFit.bounds(
                      bounds: LatLngBounds.fromPoints(points),
                      padding: const EdgeInsets.all(56),
                      maxZoom: 16,
                    ),
                  ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png',
                userAgentPackageName: 'com.timedrop.app',
                retinaMode: RetinaMode.isHighDensity(context),
                keepBuffer: 4,
                panBuffer: 2,
                tileBuilder: (context, tileWidget, tile) {
                  if (!_tilesLoaded) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted && !_tilesLoaded) {
                        setState(() => _tilesLoaded = true);
                      }
                    });
                  }
                  return tileWidget;
                },
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: widget.target,
                    width: 44,
                    height: 44,
                    alignment: Alignment.topCenter,
                    child: const Icon(
                      Icons.location_pin,
                      size: 44,
                      color: AppColors.primary,
                    ),
                  ),
                  if (user != null)
                    Marker(
                      point: user,
                      width: 22,
                      height: 22,
                      child: const _UserDot(),
                    ),
                ],
              ),
            ],
          ),
          if (!_tilesLoaded)
            const Positioned.fill(
              child: IgnorePointer(
                child: Center(
                  child: SkeletonBox(width: 160, height: 160, borderRadius: 24),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The recipient's own position — a plain dot, deliberately quieter than the
/// destination pin so the eye goes to where they are heading.
class _UserDot extends StatelessWidget {
  const _UserDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.onSurface,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 6,
          ),
        ],
      ),
    );
  }
}
