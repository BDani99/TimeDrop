import 'dart:async';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/system_config.dart';
import '../../core/constants/app_constants.dart';
import '../../core/errors/app_exception.dart';
import '../../core/haptics/app_haptics.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/distance_motivation.dart';
import '../../models/capsule_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/capsule_provider.dart';
import '../../services/geolocation_service.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/countdown_timer.dart';
import '../widgets/loading/skeleton_box.dart';
import '../widgets/permission_gate.dart';
import '../widgets/primary_button.dart';
import '../widgets/radar/sci_fi_radar_view.dart';
import '../widgets/recipient_map_view.dart';
import '../widgets/navigation/opaque_page_route.dart';
import '../router/app_router.dart';
import 'unlock_sequence_screen.dart';

/// Finding the memory, in two halves.
///
/// **Macro** — beyond `radarSwitchMeters`, and while the clock is still
/// running: a street map showing the drop and the recipient, plus a handoff to
/// their own maps app. Following a compass needle for four kilometres is not
/// navigation, and a countdown is more useful next to a map than next to a
/// radar, because it lets someone plan the trip.
///
/// **Micro** — inside the switch distance: the map is useless for the last
/// few metres (no street map resolves "the bench by the oak"), so the sci-fi
/// radar takes over with bearing and a quickening haptic pulse.
///
/// Once the recipient is within `unlockProximityMeters` (or the fuzzy-unlock
/// condition is met) it decrypts and hands off to [UnlockSequenceScreen].
/// While the sender's background upload is still in flight, shows a
/// "materializing" state and polls until ready.
class RadarScreen extends StatefulWidget {
  const RadarScreen({
    super.key,
    required this.shareId,
    required this.encryptionKey,
    this.fromName,
  });

  final String shareId;
  final String encryptionKey;
  final String? fromName;

  @override
  State<RadarScreen> createState() => _RadarScreenState();
}

class _RadarScreenState extends State<RadarScreen> {
  bool _loadStarted = false;
  bool _loadFailed = false;
  bool _isWatching = false;
  bool _hasUnlocked = false;

  Timer? _pendingPollTimer;
  Timer? _heartbeatTimer;
  int? _heartbeatIntervalMs;

  /// Whether the proximity radar has joined the map. Held in state rather than
  /// derived fresh each build so the hysteresis below has something to hold on
  /// to. The map is on screen either way — this only adds an instrument.
  bool _showRadar = false;

  /// Reveals and hides the radar with a dead band, so GPS jitter around the
  /// threshold cannot make it flicker in and out.
  void _syncRadarVisibility(double? distance) {
    if (distance == null) return;
    final config = SystemConfig.instance;
    final next = _showRadar
        ? distance <= config.radarHideMeters
        : distance <= config.radarSwitchMeters;
    if (next == _showRadar) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _showRadar = next);
    });
  }

  /// Hands the drop's coordinates to whatever the user navigates with —
  /// as a *route*, not as a dropped pin.
  ///
  /// The Android branch used to send a bare `geo:` URI, which opens the maps
  /// app looking at the place and nothing more: the walker still had to find
  /// the directions button and start the trip themselves. Both platforms now
  /// get a directions URL with the destination, the walking mode and — when
  /// the GPS has a fix — the origin, so the route is drawn on arrival.
  Future<void> _openDirections(CapsuleModel capsule, LatLng? from) async {
    final lat = capsule.latitude;
    final lng = capsule.longitude;
    final origin = from == null ? '' : '${from.latitude},${from.longitude}';

    final candidates = <Uri>[
      if (Platform.isIOS)
        // `saddr` left empty means "from where I am" to Apple Maps; dirflg=w
        // asks for the walking route.
        Uri.parse('https://maps.apple.com/?saddr=$origin&daddr=$lat,$lng&dirflg=w')
      else
        // Caught by the Google Maps app as an App Link, and still works in a
        // browser if it is not installed.
        Uri.parse(
          'https://www.google.com/maps/dir/?api=1'
          '${origin.isEmpty ? '' : '&origin=$origin'}'
          '&destination=$lat,$lng&travelmode=walking&dir_action=navigate',
        ),
      Uri.parse(
        'https://www.google.com/maps/dir/?api=1'
        '&destination=$lat,$lng&travelmode=walking',
      ),
      // Last resort: any maps app at all, even if it only shows the place.
      Uri.parse('geo:$lat,$lng?q=$lat,$lng'),
    ];

    for (final uri in candidates) {
      try {
        if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
      } catch (_) {
        // Try the next one.
      }
    }
    if (mounted) {
      AppSnackbar.showMessage(context, 'No maps app could be opened.');
    }
  }

  @override
  void dispose() {
    _pendingPollTimer?.cancel();
    _heartbeatTimer?.cancel();
    context.read<CapsuleProvider>().stopWatchingPosition();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final userId = context.read<AuthProvider>().userId;
      if (userId == null) {
        throw const AuthException('You need to be signed in to view this memory.');
      }
      await context.read<CapsuleProvider>().loadCapsuleForRadar(
            shareId: widget.shareId,
            encryptionKey: widget.encryptionKey,
            recipientUserId: userId,
            fromName: widget.fromName,
          );
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadFailed = true);
      AppSnackbar.showError(context, e);
    }
  }

  bool _pollInFlight = false;

  void _ensurePendingPoll() {
    _pendingPollTimer ??= Timer.periodic(const Duration(seconds: 3), (_) async {
      // Timer.periodic does not wait for a previous async tick to finish
      // before scheduling the next one — without this guard, a slow or
      // hung network call would leave overlapping refreshActiveCapsule
      // calls piling up every 3 seconds.
      if (!mounted || _pollInFlight) return;
      _pollInFlight = true;
      try {
        final provider = context.read<CapsuleProvider>();
        await provider.refreshActiveCapsule();
        if (provider.activeCapsule?.isPending == false) {
          _pendingPollTimer?.cancel();
          _pendingPollTimer = null;
        }
      } catch (e) {
        // Best-effort polling — a transient failure just means the next
        // tick tries again, rather than crashing out of the timer.
        debugPrint('Pending-capsule poll failed: $e');
      } finally {
        _pollInFlight = false;
      }
    });
  }

  /// The quickening pulse. Starts at the same distance the radar appears, so
  /// the instrument and the feeling arrive together rather than the radar
  /// showing up silently and the pulse joining fifty metres later.
  void _syncHeartbeat(double? distance) {
    final revealAt = SystemConfig.instance.radarSwitchMeters;
    if (distance == null || distance >= revealAt) {
      _heartbeatTimer?.cancel();
      _heartbeatTimer = null;
      _heartbeatIntervalMs = null;
      return;
    }
    // Same 250 ms → 1400 ms span as before, stretched over the wider range so
    // the pulse still races only in the final metres.
    final t = (distance / revealAt).clamp(0.0, 1.0);
    final intervalMs = (250 + t * 1150).round();
    if (_heartbeatTimer != null &&
        _heartbeatIntervalMs != null &&
        (intervalMs - _heartbeatIntervalMs!).abs() < 120) {
      return;
    }
    _heartbeatTimer?.cancel();
    _heartbeatIntervalMs = intervalMs;
    _heartbeatTimer = Timer.periodic(Duration(milliseconds: intervalMs), (_) {
      AppHaptics.light();
    });
  }

  Color _heatColor(double? distance) {
    if (distance == null) return AppColors.surface;
    final zone = SystemConfig.instance.radarZoneRadiusMeters;
    final t = (1 - (distance / zone)).clamp(0.0, 1.0);
    return Color.lerp(AppColors.surface, AppColors.secondaryContainer, t)!;
  }

  double _proximity(double? distance) {
    if (distance == null) return 0;
    final zone = SystemConfig.instance.radarZoneRadiusMeters;
    return (1 - (distance / zone)).clamp(0.0, 1.0);
  }

  /// Where the recipient is, when the GPS has said so.
  LatLng? _userLatLng(CapsuleProvider provider) {
    final lat = provider.userLatitude;
    final lng = provider.userLongitude;
    if (lat == null || lng == null) return null;
    return LatLng(lat, lng);
  }

  void _exit() {
    _pendingPollTimer?.cancel();
    _heartbeatTimer?.cancel();
    context.read<CapsuleProvider>().stopWatchingPosition();
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      enterAppAfterRecipient(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    return Consumer<CapsuleProvider>(
      builder: (context, capsuleProvider, _) {
        final capsule = capsuleProvider.activeCapsule;
        final distance = capsuleProvider.distanceMeters;
        return Scaffold(
          backgroundColor: _heatColor(distance),
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: Icon(canPop ? Icons.arrow_back : Icons.close),
              onPressed: _exit,
            ),
          ),
          body: SafeArea(
            child: PermissionGate(
              requestPermission: GeolocationService.ensurePermissionGranted,
              deniedMessage: 'Location access is required to find this memory.',
              child: Builder(
                builder: (context) {
                  if (!_loadStarted) {
                    _loadStarted = true;
                    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
                  }
                  if (_loadFailed) return _ErrorState(onBackHome: _exit);
                  if (capsuleProvider.isLoadingRadar || capsule == null) {
                    return const _RadarSkeleton();
                  }
                  if (capsule.isPending) {
                    _ensurePendingPoll();
                    return const _MaterializingState();
                  }
                  return _buildPhase(context, capsuleProvider, capsule);
                },
              ),
            ),
          ),
        );
      },
    );
  }

  /// The map, the distance and the handoff to the user's own maps app — the
  /// part of this screen that is always on.
  ///
  /// It fills whatever height the layout can spare instead of the fixed 280 px
  /// it used to take, because it is no longer one of two alternating panels.
  /// The distance chip is layered on top of the map rather than left in the
  /// subtitle: it has to survive every phase, including the ones that put
  /// something else in the headline.
  Widget _mapSection(CapsuleProvider provider, CapsuleModel capsule) {
    final user = _userLatLng(provider);

    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: RecipientMapView(
                  key: ValueKey('map-${capsule.id}'),
                  target: LatLng(capsule.latitude, capsule.longitude),
                  userLocation: user,
                ),
              ),
              const Positioned(
                left: AppSpacing.sm,
                bottom: AppSpacing.sm,
                child: _DistanceChip(),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        OutlinedButton.icon(
          onPressed: () => _openDirections(capsule, user),
          icon: const Icon(Icons.directions_outlined, size: 18),
          label: const Text('Get directions'),
        ),
      ],
    );
  }

  Widget _buildPhase(BuildContext context, CapsuleProvider provider, CapsuleModel capsule) {
    final distance = provider.distanceMeters;
    final proximity = _proximity(distance);
    final closing = distance != null && distance < AppConstants.radarClosingMeters;

    switch (provider.radarPhase) {
      case RadarPhase.locating:
        return const _RadarSkeleton();

      case RadarPhase.waiting:
        // GPS runs during the wait too, so the map can show how far they are
        // and "Get directions" is useful for planning the trip.
        if (!_isWatching) {
          _isWatching = true;
          WidgetsBinding.instance.addPostFrameCallback((_) => provider.startWatchingPosition());
        }
        return _RadarLayout(
          title: 'A memory is waiting for you.',
          subtitle: 'It opens in:',
          header: CountdownTimer(target: capsule.unlockTime),
          child: _mapSection(provider, capsule),
        );

      case RadarPhase.searching:
        if (!_isWatching) {
          _isWatching = true;
          WidgetsBinding.instance.addPostFrameCallback((_) => provider.startWatchingPosition());
        }
        WidgetsBinding.instance.addPostFrameCallback((_) => _syncHeartbeat(distance));
        _syncRadarVisibility(distance);
        // Decrypt in progress after proximity — keep the radar UI but show
        // a clear "opening" state instead of jumping to a stuck spinner.
        if (provider.unlockError != null) {
          return _RadarLayout(
            title: 'Could not open this memory.',
            subtitle: 'Check your connection and try again.',
            child: PrimaryButton(
              label: 'Go back',
              onPressed: _exit,
            ),
          );
        }
        if (provider.isUnlocking) {
          return const _RadarLayout(
            title: 'Opening your memory…',
            subtitle: 'Decrypting securely.',
            child: SizedBox(
              width: 72,
              height: 72,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: AppColors.primary,
              ),
            ),
          );
        }
        // The map never leaves. Close in and the radar grows in underneath it,
        // as a second instrument rather than a replacement — the street map is
        // what got them here and it is still the only thing that can show them
        // the last corner.
        return _RadarLayout(
          title: _showRadar
              ? DistanceMotivation.titleFor(distance, isClosing: closing)
              : 'Head to the spot.',
          subtitle: distance != null
              ? DistanceMotivation.messageFor(distance)
              : 'Finding your position…',
          footer: _RadarReveal(
            visible: _showRadar,
            distanceMeters: distance,
            proximity: proximity,
          ),
          child: _mapSection(provider, capsule),
        );

      case RadarPhase.unlocked:
        // Media is guaranteed ready when the provider flips to unlocked.
        final mediaBytes = provider.decryptedMediaBytes;
        final metadata = provider.decryptedMetadata;
        if (mediaBytes == null || metadata == null) {
          return const _RadarLayout(
            title: 'The moment is yours.',
            child: SizedBox(
              width: 72,
              height: 72,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: AppColors.primary,
              ),
            ),
          );
        }
        if (!_hasUnlocked) {
          _hasUnlocked = true;
          _heartbeatTimer?.cancel();
          final note = provider.decryptedNote;
          final photos = List<Uint8List>.from(provider.decryptedPhotos);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            Navigator.pushReplacement(
              context,
              OpaquePageRoute(
                page: UnlockSequenceScreen(
                  mediaBytes: mediaBytes,
                  mimeType: metadata.mimeType,
                  note: note,
                  photos: photos,
                  capturedAt: metadata.capturedAt,
                  capsuleId: capsule.id,
                  latitude: capsule.latitude,
                  longitude: capsule.longitude,
                  fromName: widget.fromName,
                  placeLabel: capsule.city,
                  distanceMeters: distance,
                ),
              ),
            );
          });
        }
        return const _RadarLayout(
          title: 'The moment is yours.',
          child: SizedBox(
            width: 72,
            height: 72,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: AppColors.primary,
            ),
          ),
        );
    }
  }
}

/// The common shell: a compact headline, then whatever the phase puts on
/// screen, taking all the height that is left.
///
/// This used to be a `SingleChildScrollView` around a centred column, because
/// the phases stacked a countdown, a fixed 280 px map and a button, and that
/// overflowed a small phone. Nothing here is fixed-height any more — the map
/// takes the slack — so there is no scroll and no reason for one. A map you
/// have to scroll to is a map you cannot glance at, which was the whole
/// complaint.
class _RadarLayout extends StatelessWidget {
  const _RadarLayout({
    required this.title,
    required this.child,
    this.subtitle,
    this.header,
    this.footer,
  });

  final String title;
  final String? subtitle;

  /// Sits between the headline and [child]. The countdown, while waiting.
  final Widget? header;

  /// The body. Given every pixel the headline and footer do not take.
  final Widget child;

  /// Beneath the body: the proximity radar, once it is close enough to matter.
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.containerMargin),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title,
              style: AppTypography.headlineMd, textAlign: TextAlign.center),
          if (subtitle != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              subtitle!,
              style:
                  AppTypography.bodyMd.copyWith(color: AppColors.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
          if (header case final headerWidget?) ...[
            const SizedBox(height: AppSpacing.sm),
            Center(child: headerWidget),
          ],
          const SizedBox(height: AppSpacing.md),
          Expanded(child: Center(child: child)),
          ?footer,
        ],
      ),
    );
  }
}

/// Always-on distance readout, layered over the map.
///
/// It reads the provider directly instead of taking a value, because the GPS
/// stream notifies every metre walked: passing the number down would rebuild
/// the map with it, and rebuilding a `FlutterMap` once a second is not free.
class _DistanceChip extends StatelessWidget {
  const _DistanceChip();

  @override
  Widget build(BuildContext context) {
    final distance = context.select<CapsuleProvider, double?>(
      (p) => p.distanceMeters,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.92),
        borderRadius: const BorderRadius.all(Radius.circular(999)),
        boxShadow: const [
          BoxShadow(color: Color(0x1A000000), blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm + 2,
          vertical: AppSpacing.xs + 2,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              distance == null ? Icons.gps_not_fixed : Icons.straighten,
              size: 14,
              color: AppColors.onSurfaceVariant,
            ),
            const SizedBox(width: AppSpacing.xs),
            Text(
              distance == null
                  ? 'Locating you…'
                  : '${DistanceMotivation.formatDistance(distance)} away',
              style: AppTypography.labelSm.copyWith(
                color: AppColors.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The proximity radar growing in beneath the map, and shrinking away again if
/// the walker drifts back out. Sized rather than faded so the map gives up its
/// height smoothly instead of the radar landing on top of it.
class _RadarReveal extends StatelessWidget {
  const _RadarReveal({
    required this.visible,
    required this.distanceMeters,
    required this.proximity,
  });

  final bool visible;
  final double? distanceMeters;
  final double proximity;

  @override
  Widget build(BuildContext context) {
    // Never more than a third of the screen. The map is the thing that has to
    // survive this — a fixed radar height would eat a short phone's map down to
    // a strip at exactly the moment the walker is checking it most often.
    final maxHeight =
        (MediaQuery.sizeOf(context).height * 0.28).clamp(140.0, 220.0);

    return AnimatedSize(
      duration: const Duration(milliseconds: 520),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: !visible
          ? const SizedBox(width: double.infinity, height: 0)
          : Padding(
              padding: const EdgeInsets.only(top: AppSpacing.md),
              child: SizedBox(
                height: maxHeight,
                child: Center(
                  child: SciFiRadarView(
                    distanceMeters: distanceMeters,
                    proximity: proximity,
                  ),
                ),
              ),
            ),
    );
  }
}

class _RadarSkeleton extends StatelessWidget {
  const _RadarSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.containerMargin),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          SkeletonBox(width: 220, height: 28),
          SizedBox(height: AppSpacing.lg),
          SkeletonBox(width: double.infinity, height: 280, borderRadius: 28),
        ],
      ),
    );
  }
}

class _MaterializingState extends StatelessWidget {
  const _MaterializingState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.containerMargin),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SkeletonBox(width: double.infinity, height: 280, borderRadius: 28),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Almost ready…',
            style: AppTypography.headlineMd,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'The sender\'s memory is still being sealed — this takes a moment.',
            style: AppTypography.bodyMd.copyWith(color: AppColors.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onBackHome});

  final VoidCallback onBackHome;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.containerMargin),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'This memory could not be found.',
              style: AppTypography.bodyMd,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.md),
            PrimaryButton(label: 'Back to home', onPressed: onBackHome),
          ],
        ),
      ),
    );
  }
}
