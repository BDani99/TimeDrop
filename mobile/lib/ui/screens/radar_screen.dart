import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
import '../widgets/navigation/opaque_page_route.dart';
import '../router/app_router.dart';
import 'unlock_sequence_screen.dart';

/// Post-unlock-link screen: waits for the unlock time, then streams GPS
/// position until the recipient is within `unlockProximityMeters` of the
/// capsule (or the fuzzy-unlock condition is met), at which point it decrypts
/// and hands off to [UnlockSequenceScreen]. While the sender's background upload
/// is still in flight, shows a "materializing" state and polls until ready.
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

  void _ensurePendingPoll() {
    _pendingPollTimer ??= Timer.periodic(const Duration(seconds: 3), (_) async {
      if (!mounted) return;
      final provider = context.read<CapsuleProvider>();
      await provider.refreshActiveCapsule();
      if (provider.activeCapsule?.isPending == false) {
        _pendingPollTimer?.cancel();
        _pendingPollTimer = null;
      }
    });
  }

  void _syncHeartbeat(double? distance) {
    if (distance == null || distance >= AppConstants.radarClosingMeters) {
      _heartbeatTimer?.cancel();
      _heartbeatTimer = null;
      _heartbeatIntervalMs = null;
      return;
    }
    final t = (distance / AppConstants.radarClosingMeters).clamp(0.0, 1.0);
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

  double? _bearing(CapsuleProvider provider, CapsuleModel capsule) {
    final lat = provider.userLatitude;
    final lng = provider.userLongitude;
    if (lat == null || lng == null) return null;
    return GeolocationService.bearingDegrees(
      startLat: lat,
      startLng: lng,
      endLat: capsule.latitude,
      endLng: capsule.longitude,
    );
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

  Widget _buildPhase(BuildContext context, CapsuleProvider provider, CapsuleModel capsule) {
    final distance = provider.distanceMeters;
    final proximity = _proximity(distance);
    final bearing = _bearing(provider, capsule);
    final closing = distance != null && distance < AppConstants.radarClosingMeters;

    switch (provider.radarPhase) {
      case RadarPhase.locating:
        return const _RadarSkeleton();

      case RadarPhase.waiting:
        return _RadarLayout(
          title: 'A memory is waiting nearby.',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CountdownTimer(target: capsule.unlockTime),
              const SizedBox(height: AppSpacing.lg),
              SciFiRadarView(
                bearingDegrees: bearing,
                distanceMeters: distance,
                proximity: proximity,
              ),
            ],
          ),
        );

      case RadarPhase.searching:
        if (!_isWatching) {
          _isWatching = true;
          WidgetsBinding.instance.addPostFrameCallback((_) => provider.startWatchingPosition());
        }
        WidgetsBinding.instance.addPostFrameCallback((_) => _syncHeartbeat(distance));
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
        return _RadarLayout(
          title: DistanceMotivation.titleFor(distance, isClosing: closing),
          subtitle: distance != null ? DistanceMotivation.messageFor(distance) : null,
          child: SciFiRadarView(
            bearingDegrees: bearing,
            distanceMeters: distance,
            proximity: proximity,
          ),
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

class _RadarLayout extends StatelessWidget {
  const _RadarLayout({
    required this.title,
    required this.child,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.containerMargin),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: AppTypography.headlineMd, textAlign: TextAlign.center),
          if (subtitle != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              subtitle!,
              style: AppTypography.bodyMd.copyWith(color: AppColors.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          Center(child: child),
        ],
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
            'Materializing your memory…',
            style: AppTypography.headlineMd,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'The capsule is still sealing in the cloud.',
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
            PrimaryButton(label: 'Back to Home', onPressed: onBackHome),
          ],
        ),
      ),
    );
  }
}
