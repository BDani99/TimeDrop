import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../services/geolocation_service.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/permission_gate.dart';
import 'capsule_config_screen.dart';

/// Full-screen video recorder. Wrapped in [PermissionGate] so camera +
/// microphone access is confirmed *before* the [CameraController] is ever
/// initialized, per the cross-cutting permission rule. Location is requested
/// separately and non-blockingly (for the live watermark only) so a missing
/// location never blocks recording.
class CameraScreen extends StatelessWidget {
  const CameraScreen({super.key});

  static Future<bool> _requestPermissions() async {
    final statuses = await [Permission.camera, Permission.microphone].request();
    return statuses.values.every((status) => status.isGranted);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: PermissionGate(
        requestPermission: _requestPermissions,
        deniedMessage: 'Camera and microphone access are required to record a memory.',
        child: const _CameraBody(),
      ),
    );
  }
}

/// 3-state flash cycle: Auto → On (torch) → Off. On video, torch is the only
/// mode that yields continuous light; auto/off map to the camera FlashModes.
enum _FlashState { auto, on, off }

extension _FlashStateX on _FlashState {
  _FlashState get next => switch (this) {
        _FlashState.auto => _FlashState.on,
        _FlashState.on => _FlashState.off,
        _FlashState.off => _FlashState.auto,
      };

  FlashMode get mode => switch (this) {
        _FlashState.auto => FlashMode.auto,
        _FlashState.on => FlashMode.torch,
        _FlashState.off => FlashMode.off,
      };

  IconData get icon => switch (this) {
        _FlashState.auto => Icons.flash_auto,
        _FlashState.on => Icons.flash_on,
        _FlashState.off => Icons.flash_off,
      };
}

class _CameraBody extends StatefulWidget {
  const _CameraBody();

  @override
  State<_CameraBody> createState() => _CameraBodyState();
}

class _CameraBodyState extends State<_CameraBody> with SingleTickerProviderStateMixin {
  CameraController? _controller;
  List<CameraDescription> _cameras = const [];
  CameraLensDirection _lensDirection = CameraLensDirection.back;
  _FlashState _flash = _FlashState.off;

  bool _isRecording = false;
  bool _isSwitching = false;
  DateTime? _recordingStart;
  Timer? _autoStopTimer;

  late final AnimationController _ringController;

  StreamSubscription<Position>? _positionSubscription;
  Position? _position;

  @override
  void initState() {
    super.initState();
    _ringController = AnimationController(
      vsync: this,
      duration: AppConstants.maxRecordingDuration,
    );
    _initCamera();
    _initLocationWatermark();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw Exception('No camera available on this device.');
      }
      _cameras = cameras;
      await _createController(_lensDirection);
    } catch (e) {
      if (mounted) AppSnackbar.showError(context, e);
    }
  }

  Future<void> _createController(CameraLensDirection direction) async {
    final camera = _cameras.firstWhere(
      (c) => c.lensDirection == direction,
      orElse: () => _cameras.first,
    );
    final controller = CameraController(
      camera,
      ResolutionPreset.high,
      enableAudio: true,
    );
    await controller.initialize();
    // Front cameras rarely support a flash — reset to Off when unavailable.
    try {
      await controller.setFlashMode(_flash.mode);
    } catch (_) {
      _flash = _FlashState.off;
    }
    if (!mounted) {
      await controller.dispose();
      return;
    }
    setState(() {
      _controller = controller;
      _lensDirection = camera.lensDirection;
    });
  }

  /// Non-blocking: only used to show live coordinates on the watermark.
  /// Recording works regardless of whether this succeeds.
  Future<void> _initLocationWatermark() async {
    try {
      final granted = await GeolocationService.ensurePermissionGranted();
      if (!granted || !mounted) return;
      _positionSubscription = GeolocationService.watchPosition().listen((position) {
        if (mounted) setState(() => _position = position);
      });
    } catch (_) {
      // Watermark simply shows date-only.
    }
  }

  Future<void> _switchCamera() async {
    if (_isSwitching || _isRecording || _cameras.length < 2) return;
    setState(() => _isSwitching = true);
    final target = _lensDirection == CameraLensDirection.back
        ? CameraLensDirection.front
        : CameraLensDirection.back;
    try {
      await _controller?.dispose();
      _controller = null;
      await _createController(target);
    } catch (e) {
      if (mounted) AppSnackbar.showError(context, e);
    } finally {
      if (mounted) setState(() => _isSwitching = false);
    }
  }

  Future<void> _cycleFlash() async {
    final controller = _controller;
    if (controller == null) return;
    final next = _flash.next;
    try {
      await controller.setFlashMode(next.mode);
      setState(() => _flash = next);
    } catch (e) {
      if (mounted) AppSnackbar.showError(context, e);
    }
  }

  Future<void> _startRecording() async {
    final controller = _controller;
    if (controller == null || _isRecording) return;
    try {
      await controller.startVideoRecording();
      _recordingStart = DateTime.now();
      HapticFeedback.lightImpact();
      _ringController.forward(from: 0);
      setState(() => _isRecording = true);
      _autoStopTimer = Timer(AppConstants.maxRecordingDuration, _stopRecording);
    } catch (e) {
      if (mounted) AppSnackbar.showError(context, e);
    }
  }

  Future<void> _stopRecording() async {
    final controller = _controller;
    if (controller == null || !_isRecording) return;
    _autoStopTimer?.cancel();
    _ringController.stop();
    _ringController.reset();
    try {
      final file = await controller.stopVideoRecording();
      HapticFeedback.lightImpact();
      final start = _recordingStart;
      final durationMs = start != null ? DateTime.now().difference(start).inMilliseconds : 0;
      if (mounted) setState(() => _isRecording = false);
      if (!mounted) return;
      // Pass the file PATH (not bytes) so the full video never lives in
      // memory across screens — the OOM fix.
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CapsuleConfigScreen(
            videoPath: file.path,
            mimeType: 'video/mp4',
            durationMs: durationMs,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isRecording = false);
        AppSnackbar.showError(context, e);
      }
    }
  }

  @override
  void dispose() {
    _autoStopTimer?.cancel();
    _positionSubscription?.cancel();
    _ringController.dispose();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _isSwitching) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }

    final flashAvailable = _lensDirection == CameraLensDirection.back;

    return Stack(
      children: [
        // CameraPreview wraps its texture in an AspectRatio that, given the
        // loose constraints from a plain Positioned.fill, sizes itself down
        // to the texture's small natural size instead of filling the
        // screen (a well-known `camera` plugin layout quirk). Forcing tight
        // constraints via LayoutBuilder + FittedBox(cover) makes it fill
        // the screen and crop to match, like a native full-screen preview.
        Positioned.fill(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return ClipRect(
                child: OverflowBox(
                  alignment: Alignment.center,
                  child: FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: constraints.maxWidth,
                      height: constraints.maxWidth * controller.value.aspectRatio,
                      child: CameraPreview(controller),
                    ),
                  ),
                ),
              );
            },
          ),
        ),

        // Live date + GPS watermark (overlay only — not burned into video).
        Positioned(
          left: AppSpacing.md,
          bottom: 120,
          child: _Watermark(position: _position),
        ),

        SafeArea(
          child: Stack(
            children: [
              // Flash (top-left).
              if (flashAvailable)
                Positioned(
                  top: AppSpacing.sm,
                  left: AppSpacing.sm,
                  child: _CircleIconButton(icon: _flash.icon, onTap: _cycleFlash),
                ),

              // Selfie toggle (top-right).
              if (_cameras.length > 1)
                Positioned(
                  top: AppSpacing.sm,
                  right: AppSpacing.sm,
                  child: _CircleIconButton(
                    icon: Icons.cameraswitch,
                    onTap: _isRecording ? null : _switchCamera,
                  ),
                ),

              // Micro-copy + record button (bottom-center).
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 40),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedOpacity(
                        opacity: _isRecording ? 0 : 1,
                        duration: const Duration(milliseconds: 250),
                        child: Text(
                          'Tap to lock the moment',
                          style: AppTypography.labelMd.copyWith(color: Colors.white70),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      _RecordButton(
                        isRecording: _isRecording,
                        progress: _ringController,
                        onTap: _isRecording ? _stopRecording : _startRecording,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The gamified record button: a primary-colored progress ring fills over
/// [AppConstants.maxRecordingDuration] while recording.
class _RecordButton extends StatelessWidget {
  const _RecordButton({
    required this.isRecording,
    required this.progress,
    required this.onTap,
  });

  final bool isRecording;
  final Animation<double> progress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 84,
        height: 84,
        child: Stack(
          alignment: Alignment.center,
          children: [
            AnimatedBuilder(
              animation: progress,
              builder: (context, _) {
                return SizedBox(
                  width: 84,
                  height: 84,
                  child: CircularProgressIndicator(
                    value: isRecording ? progress.value : 0,
                    strokeWidth: 5,
                    backgroundColor: Colors.white24,
                    valueColor: const AlwaysStoppedAnimation(AppColors.primary),
                  ),
                );
              },
            ),
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isRecording ? AppColors.error : AppColors.primary,
                border: Border.all(color: Colors.white, width: 4),
              ),
              child: isRecording ? const Icon(Icons.stop, color: Colors.white) : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black38,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Icon(icon, color: onTap == null ? Colors.white38 : Colors.white),
        ),
      ),
    );
  }
}

/// Translucent live date + GPS overlay. English date format (e.g. OCT 24,
/// 2026); coordinates shown only once a live position is available.
class _Watermark extends StatelessWidget {
  const _Watermark({required this.position});

  final Position? position;

  static const _months = [
    'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
    'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
  ];

  String _formatDate(DateTime now) {
    final month = _months[now.month - 1];
    return '$month ${now.day}, ${now.year}';
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final coords = position == null
        ? null
        : '${position!.latitude.toStringAsFixed(5)}, ${position!.longitude.toStringAsFixed(5)}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 3, height: 28, color: AppColors.primary),
        const SizedBox(height: AppSpacing.xs),
        Text(
          _formatDate(now),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w600,
            letterSpacing: 1,
            shadows: [Shadow(color: Colors.black54, blurRadius: 6)],
          ),
        ),
        if (coords != null)
          Text(
            coords,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontFeatures: [FontFeature.tabularFigures()],
              shadows: [Shadow(color: Colors.black54, blurRadius: 6)],
            ),
          ),
      ],
    );
  }
}
