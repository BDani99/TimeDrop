import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../core/config/system_config.dart';
import '../../core/constants/app_constants.dart';
import '../../core/errors/app_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../models/capsule_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/capsule_provider.dart';
import '../../services/geolocation_service.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/countdown_timer.dart';
import '../widgets/permission_gate.dart';
import '../widgets/primary_button.dart';
import '../widgets/radar_view.dart';
import '../router/app_router.dart';
import 'video_player_screen.dart';

/// Post-unlock-link screen: waits for the unlock time, then streams GPS
/// position until the recipient is within `unlockProximityMeters` of the
/// capsule (or the fuzzy-unlock condition is met), at which point it decrypts
/// and hands off to [VideoPlayerScreen]. While the sender's background upload
/// is still in flight, shows a "materializing" state and polls until ready.
///
/// Constructor shape MUST match `app_router.dart`'s
/// `RadarScreen(key: ..., shareId: ..., encryptionKey: ...)` call site.
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

  /// Haptic "heartbeat" that pulses faster as the recipient closes in (within
  /// the closing zone). Cancelled outside the zone / once unlocked.
  void _syncHeartbeat(double? distance) {
    if (distance == null || distance >= AppConstants.radarClosingMeters) {
      _heartbeatTimer?.cancel();
      _heartbeatTimer = null;
      _heartbeatIntervalMs = null;
      return;
    }
    final t = (distance / AppConstants.radarClosingMeters).clamp(0.0, 1.0);
    final intervalMs = (250 + t * 1150).round(); // 250ms (very close) → 1400ms
    if (_heartbeatTimer != null &&
        _heartbeatIntervalMs != null &&
        (intervalMs - _heartbeatIntervalMs!).abs() < 120) {
      return; // avoid thrashing the timer on tiny distance jitter
    }
    _heartbeatTimer?.cancel();
    _heartbeatIntervalMs = intervalMs;
    _heartbeatTimer = Timer.periodic(Duration(milliseconds: intervalMs), (_) {
      HapticFeedback.lightImpact();
    });
  }

  /// Warm "heatmap" background: cream far away → soft apricot as you close.
  /// Uses the on-brand [AppColors.secondaryContainer] rather than the saturated
  /// primary container so the shift stays within the Golden Hour palette.
  Color _heatColor(double? distance) {
    if (distance == null) return AppColors.surface;
    final zone = SystemConfig.instance.radarZoneRadiusMeters;
    final t = (1 - (distance / zone)).clamp(0.0, 1.0);
    return Color.lerp(AppColors.surface, AppColors.secondaryContainer, t)!;
  }

  /// Exit affordance. From the Gallery it pops back; as the recipient-clipboard
  /// root it enters the app (onboarding-gated for new users).
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
                    return const Center(child: CircularProgressIndicator(color: AppColors.primary));
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
    final center = LatLng(capsule.latitude, capsule.longitude);
    final distance = provider.distanceMeters;

    switch (provider.radarPhase) {
      case RadarPhase.locating:
        return const Center(child: CircularProgressIndicator(color: AppColors.primary));

      case RadarPhase.waiting:
        return _RadarLayout(
          title: 'A memory is waiting nearby.',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CountdownTimer(target: capsule.unlockTime),
              const SizedBox(height: AppSpacing.lg),
              RadarView(
                center: center,
                radiusMeters: SystemConfig.instance.radarZoneRadiusMeters,
                distanceMeters: null,
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
        final closing = distance != null && distance < AppConstants.radarClosingMeters;
        return _RadarLayout(
          title: closing ? 'You are getting closer...' : 'Find the spot to unlock it.',
          child: RadarView(
            center: center,
            radiusMeters: SystemConfig.instance.radarZoneRadiusMeters,
            distanceMeters: distance,
          ),
        );

      case RadarPhase.unlocked:
        if (!_hasUnlocked) {
          _hasUnlocked = true;
          _heartbeatTimer?.cancel();
          HapticFeedback.heavyImpact();
          final mediaBytes = provider.decryptedMediaBytes;
          final metadata = provider.decryptedMetadata;
          final note = provider.decryptedNote;
          final photos = provider.decryptedPhotos;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || mediaBytes == null || metadata == null) return;
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => VideoPlayerScreen(
                  mediaBytes: mediaBytes,
                  mimeType: metadata.mimeType,
                  note: note,
                  photos: photos,
                ),
              ),
            );
          });
        }
        return _RadarLayout(
          title: 'The moment is yours.',
          child: const CircularProgressIndicator(color: AppColors.primary),
        );
    }
  }
}

class _RadarLayout extends StatelessWidget {
  const _RadarLayout({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.containerMargin),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(title, style: AppTypography.headlineMd, textAlign: TextAlign.center),
          const SizedBox(height: AppSpacing.lg),
          child,
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
          const LinearProgressIndicator(color: AppColors.primary),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'The capsule is still materializing in the cloud...',
            style: AppTypography.headlineMd,
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
