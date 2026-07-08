import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../providers/capsule_provider.dart';
import '../../services/geolocation_service.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/countdown_timer.dart';
import '../widgets/permission_gate.dart';
import '../widgets/primary_button.dart';
import '../widgets/radar_view.dart';
import 'home_screen.dart';
import 'video_player_screen.dart';

/// Post-unlock-link screen: waits for the unlock time, then streams GPS
/// position until the recipient is within `unlockProximityMeters` of the
/// capsule, at which point it decrypts and hands off to [VideoPlayerScreen].
///
/// Constructor shape MUST match `app_router.dart`'s
/// `RadarScreen(key: ..., shareId: ..., encryptionKey: ...)` call site.
class RadarScreen extends StatefulWidget {
  const RadarScreen({super.key, required this.shareId, required this.encryptionKey});

  final String shareId;
  final String encryptionKey;

  @override
  State<RadarScreen> createState() => _RadarScreenState();
}

class _RadarScreenState extends State<RadarScreen> {
  bool _loadStarted = false;
  bool _loadFailed = false;
  bool _isWatching = false;
  bool _hasUnlocked = false;

  @override
  void dispose() {
    context.read<CapsuleProvider>().stopWatchingPosition();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      await context.read<CapsuleProvider>().loadCapsuleForRadar(
            shareId: widget.shareId,
            encryptionKey: widget.encryptionKey,
          );
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadFailed = true);
      AppSnackbar.showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
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

              if (_loadFailed) {
                return _ErrorState(
                  onBackHome: () => Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => const HomeScreen()),
                    (route) => false,
                  ),
                );
              }

              return Consumer<CapsuleProvider>(
                builder: (context, capsuleProvider, _) {
                  final capsule = capsuleProvider.activeCapsule;
                  if (capsuleProvider.isLoadingRadar || capsule == null) {
                    return const Center(
                      child: CircularProgressIndicator(color: AppColors.primary),
                    );
                  }

                  final center = LatLng(capsule.latitude, capsule.longitude);

                  switch (capsuleProvider.radarPhase) {
                    case RadarPhase.locating:
                      return const Center(
                        child: CircularProgressIndicator(color: AppColors.primary),
                      );

                    case RadarPhase.waiting:
                      return Padding(
                        padding: const EdgeInsets.all(AppSpacing.containerMargin),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('A memory is waiting nearby', style: AppTypography.headlineMd),
                            const SizedBox(height: AppSpacing.sm),
                            CountdownTimer(target: capsule.unlockTime),
                            const SizedBox(height: AppSpacing.lg),
                            RadarView(
                              center: center,
                              radiusMeters: AppConstants.radarZoneRadiusMeters,
                              distanceMeters: null,
                            ),
                          ],
                        ),
                      );

                    case RadarPhase.searching:
                      if (!_isWatching) {
                        _isWatching = true;
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          capsuleProvider.startWatchingPosition();
                        });
                      }
                      return Padding(
                        padding: const EdgeInsets.all(AppSpacing.containerMargin),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('Find the spot to unlock it', style: AppTypography.headlineMd),
                            const SizedBox(height: AppSpacing.lg),
                            RadarView(
                              center: center,
                              radiusMeters: AppConstants.radarZoneRadiusMeters,
                              distanceMeters: capsuleProvider.distanceMeters,
                            ),
                          ],
                        ),
                      );

                    case RadarPhase.unlocked:
                      if (!_hasUnlocked) {
                        _hasUnlocked = true;
                        HapticFeedback.mediumImpact();
                        final mediaBytes = capsuleProvider.decryptedMediaBytes;
                        final metadata = capsuleProvider.decryptedMetadata;
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (!mounted || mediaBytes == null || metadata == null) return;
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (_) => VideoPlayerScreen(
                                mediaBytes: mediaBytes,
                                mimeType: metadata.mimeType,
                              ),
                            ),
                          );
                        });
                      }
                      return const Center(
                        child: CircularProgressIndicator(color: AppColors.primary),
                      );
                  }
                },
              );
            },
          ),
        ),
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
