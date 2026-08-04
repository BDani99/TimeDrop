import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import 'loading/skeleton_box.dart';

/// The recipient's overview map: where the memory is, where they are, and how
/// far apart those are.
///
/// This is the *macro* half of finding a drop. The radar is excellent at the
/// last fifty metres and useless at four kilometres — a compass needle is not
/// navigation. Here the user gets a real street map and can hand the
/// coordinates to their own maps app.
///
/// **The camera never moves on its own.** It used to refit itself the instant
/// the first GPS fix landed, which meant the map visibly jumped a second or two
/// after it appeared — and again whenever the walker had covered sixty metres.
/// Instead the map waits for a fix (or gives up after [_locateGrace]) and is
/// then built *once*, framed correctly from its very first frame. Recentring
/// afterwards is the user's call, via the button in the corner.
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

class _RecipientMapViewState extends State<RecipientMapView>
    with SingleTickerProviderStateMixin {
  final MapController _controller = MapController();
  bool _tilesLoaded = false;

  /// How long the map waits for a first fix before drawing itself around the
  /// target alone. Long enough for a warm GPS, short enough that a recipient
  /// indoors is not left staring at a placeholder.
  static const Duration _locateGrace = Duration(milliseconds: 2500);

  /// The camera's framing, decided exactly once. Non-null means the map is
  /// built, and nothing repositions it after that except the user.
  ///
  /// Held as a single cached instance rather than rebuilt each time because
  /// [MapOptions] has no cheap equality for a [CameraFit]: a fresh one every
  /// build makes flutter_map treat the options as changed and push a new
  /// controller state on every GPS tick, once a second, for nothing.
  MapOptions? _options;
  Timer? _graceTimer;

  bool get _framed => _options != null;

  late final AnimationController _cameraAnimation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );

  @override
  void initState() {
    super.initState();
    if (widget.userLocation != null) {
      _options = _buildOptions(widget.userLocation);
    } else {
      _graceTimer = Timer(_locateGrace, () {
        if (mounted && !_framed) {
          // Still no fix: frame on the destination alone rather than leave the
          // recipient looking at a placeholder.
          setState(() => _options = _buildOptions(null));
        }
      });
    }
  }

  @override
  void didUpdateWidget(covariant RecipientMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The first fix is the only one that decides anything. Every later one just
    // moves the dot — deliberately, so the map stays where the user left it.
    if (!_framed && widget.userLocation != null) {
      _graceTimer?.cancel();
      setState(() => _options = _buildOptions(widget.userLocation));
    }
  }

  MapOptions _buildOptions(LatLng? user) {
    final fit = _fitFor(user);
    return fit == null
        ? MapOptions(initialCenter: widget.target, initialZoom: 15)
        : MapOptions(initialCameraFit: fit);
  }

  @override
  void dispose() {
    _graceTimer?.cancel();
    _cameraAnimation.dispose();
    super.dispose();
  }

  CameraFit? _fitFor(LatLng? user) {
    if (user == null) return null;
    return CameraFit.bounds(
      bounds: LatLngBounds.fromPoints([widget.target, user]),
      padding: const EdgeInsets.all(56),
      maxZoom: 16,
    );
  }

  /// Brings both points back into frame, smoothly. flutter_map has no animated
  /// camera of its own, so this drives `move` from a controller — a jump is
  /// exactly the thing this widget exists to avoid, even when asked for.
  void _recentre() {
    final user = widget.userLocation;
    final camera = _controller.camera;
    final fit = _fitFor(user);

    final LatLng targetCentre;
    final double targetZoom;
    if (fit != null) {
      final fitted = fit.fit(camera);
      targetCentre = fitted.center;
      targetZoom = fitted.zoom;
    } else {
      targetCentre = widget.target;
      targetZoom = 15;
    }

    final startCentre = camera.center;
    final startZoom = camera.zoom;

    void tick() {
      final t = Curves.easeOutCubic.transform(_cameraAnimation.value);
      _controller.move(
        LatLng(
          startCentre.latitude +
              (targetCentre.latitude - startCentre.latitude) * t,
          startCentre.longitude +
              (targetCentre.longitude - startCentre.longitude) * t,
        ),
        startZoom + (targetZoom - startZoom) * t,
      );
    }

    _cameraAnimation
      ..removeListener(tick)
      ..reset()
      ..addListener(tick)
      ..forward().whenComplete(() => _cameraAnimation.removeListener(tick));
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: AppRadii.lgRadius,
      child: Stack(
        children: [
          const Positioned.fill(
            child: ColoredBox(color: AppColors.surfaceContainer),
          ),
          if (_framed) _buildMap(context) else const _LocatingPlaceholder(),
          if (_framed && !_tilesLoaded)
            const Positioned.fill(
              child: IgnorePointer(
                child: Center(
                  child: SkeletonBox(width: 160, height: 160, borderRadius: 24),
                ),
              ),
            ),
          if (_framed)
            Positioned(
              right: AppSpacing.sm,
              bottom: AppSpacing.sm,
              child: _RecentreButton(onPressed: _recentre),
            ),
        ],
      ),
    );
  }

  Widget _buildMap(BuildContext context) {
    final user = widget.userLocation;

    return FlutterMap(
      mapController: _controller,
      options: _options!,
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
    );
  }
}

/// What stands in for the map until the framing is decided. Small and quiet on
/// purpose: this is a two-second wait, not a loading screen.
class _LocatingPlaceholder extends StatelessWidget {
  const _LocatingPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SkeletonBox(width: 160, height: 160, borderRadius: 24),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Locating your position…',
            style: AppTypography.labelSm
                .copyWith(color: AppColors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// Puts both points back on screen after the user has panned away. The map
/// never does this by itself, so this is the way back.
class _RecentreButton extends StatelessWidget {
  const _RecentreButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface.withValues(alpha: 0.92),
      shape: const CircleBorder(),
      elevation: 2,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: const Padding(
          padding: EdgeInsets.all(AppSpacing.sm),
          child: Icon(
            Icons.my_location,
            size: 20,
            color: AppColors.onSurfaceVariant,
          ),
        ),
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
