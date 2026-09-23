import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/haptics/app_haptics.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../services/geolocation_service.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/glass/glass_panel.dart';
import '../widgets/loading/skeleton_box.dart';
import '../widgets/navigation/spring_page_route.dart';
import '../widgets/permission_gate.dart';
import '../widgets/watermark_stamp.dart';
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
      body: Stack(
        children: [
          PermissionGate(
            requestPermission: _requestPermissions,
            deniedMessage: 'Camera and microphone access are required to record a memory.',
            child: const _CameraBody(),
          ),
          // A persistent close button, deliberately a sibling of
          // PermissionGate (not inside its child) so it survives the
          // pending/denied states too — without it, a denied-permission
          // screen, or on iOS any state at all (SpringPageRoute has no
          // edge-swipe-back), is a dead end the user can only escape by
          // force-quitting the app. Top-right so it never collides with the
          // watermark, which owns top-left once recording is live.
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ),
        ],
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

class _CameraBodyState extends State<_CameraBody> with TickerProviderStateMixin {
  CameraController? _controller;
  List<CameraDescription> _cameras = const [];
  // Open in selfie mode by default — most memories start front-facing.
  CameraLensDirection _lensDirection = CameraLensDirection.front;
  _FlashState _flash = _FlashState.off;

  bool _isRecording = false;
  bool _isSwitching = false;
  DateTime? _recordingStart;
  Timer? _autoStopTimer;

  late final AnimationController _ringController;
  late final AnimationController _previewScaleController;
  late final AnimationController _lensSwitchController;
  double _previewScale = 1.0;

  StreamSubscription<Position>? _positionSubscription;
  Position? _position;

  @override
  void initState() {
    super.initState();
    _ringController = AnimationController(
      vsync: this,
      duration: AppConstants.maxRecordingDuration,
    );
    _previewScaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _lensSwitchController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
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
      await _lensSwitchController.forward(from: 0);
      await AppHaptics.light();
      await _controller?.dispose();
      _controller = null;
      await _createController(target);
      await _lensSwitchController.reverse();
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
      await AppHaptics.medium();
      _ringController.forward(from: 0);
      _previewScaleController.forward(from: 0).then((_) {
        if (mounted) setState(() => _previewScale = 1.03);
      });
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
      await AppHaptics.medium();
      setState(() => _previewScale = 1.0);
      final start = _recordingStart;
      final durationMs = start != null ? DateTime.now().difference(start).inMilliseconds : 0;
      if (mounted) setState(() => _isRecording = false);
      if (!mounted) return;
      // Pass the file PATH (not bytes) so the full video never lives in
      // memory across screens — the OOM fix.
      Navigator.push(
        context,
        SpringPageRoute(
          page: CapsuleConfigScreen(
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
    _previewScaleController.dispose();
    _lensSwitchController.dispose();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _isSwitching) {
      return const _CameraInitPlaceholder();
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
              return Transform.scale(
                scale: _previewScale,
                child: AnimatedBuilder(
                  animation: _lensSwitchController,
                  builder: (context, child) {
                    return Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.identity()
                        ..setEntry(3, 2, 0.001)
                        ..rotateY(_lensSwitchController.value * 3.14159),
                      child: child,
                    );
                  },
                  child: ClipRect(
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
                  ),
                ),
              );
            },
          ),
        ),

        SafeArea(
          child: Stack(
            children: [
              // Timestamp / GPS watermark — top-left, compact.
              Positioned(
                top: AppSpacing.sm,
                left: AppSpacing.md,
                child: _Watermark(position: _position),
              ),


              // Bottom band: hint + record button. Flash sits to the left of
              // the record, camera flip to the right (always visible when
              // multiple cameras exist).
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    0,
                    AppSpacing.md,
                    32,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AnimatedOpacity(
                        opacity: _isRecording ? 0 : 1,
                        duration: const Duration(milliseconds: 250),
                        child: Text(
                          'Tap to lock the moment',
                          textAlign: TextAlign.center,
                          style: AppTypography.labelMd.copyWith(color: Colors.white70),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 56,
                            child: flashAvailable
                                ? Align(
                                    alignment: Alignment.centerLeft,
                                    child: GlassPanel(
                                      padding: const EdgeInsets.all(4),
                                      borderRadius: BorderRadius.circular(999),
                                      child: _CircleIconButton(
                                        icon: _flash.icon,
                                        onTap: _cycleFlash,
                                      ),
                                    ),
                                  )
                                : null,
                          ),
                          GlassPanel(
                            padding: const EdgeInsets.all(6),
                            borderRadius: BorderRadius.circular(999),
                            opacity: 0.55,
                            child: _RecordButton(
                              isRecording: _isRecording,
                              progress: _ringController,
                              onTap: _isRecording ? _stopRecording : _startRecording,
                            ),
                          ),
                          SizedBox(
                            width: 56,
                            child: _cameras.length > 1
                                ? Align(
                                    alignment: Alignment.centerRight,
                                    child: GlassPanel(
                                      padding: const EdgeInsets.all(4),
                                      borderRadius: BorderRadius.circular(999),
                                      child: _CircleIconButton(
                                        icon: Icons.cameraswitch,
                                        onTap: _isRecording ? null : _switchCamera,
                                      ),
                                    ),
                                  )
                                : null,
                          ),
                        ],
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

/// Wraps [WatermarkStamp] with the live GPS position from the camera screen
/// (so the same stamp component powers both recording and playback).
class _Watermark extends StatelessWidget {
  const _Watermark({required this.position});

  final Position? position;

  @override
  Widget build(BuildContext context) {
    return WatermarkStamp(
      timestamp: DateTime.now(),
    );
  }
}

/// Premium placeholder shown while the [CameraController] is initialising.
/// Replaces the jarring black-screen-with-white-circle that a plain
/// [SkeletonBox] produced. A subtle pulsing viewfinder ring communicates
/// "getting ready" without feeling like a crash or empty state.
class _CameraInitPlaceholder extends StatefulWidget {
  const _CameraInitPlaceholder();

  @override
  State<_CameraInitPlaceholder> createState() => _CameraInitPlaceholderState();
}

class _CameraInitPlaceholderState extends State<_CameraInitPlaceholder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: AnimatedBuilder(
          animation: _pulse,
          builder: (context, _) {
            final t = Curves.easeInOut.transform(_pulse.value);
            return Opacity(
              opacity: 0.25 + 0.35 * t,
              child: Transform.scale(
                scale: 0.92 + 0.08 * t,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Viewfinder outline
                    Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white, width: 2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(
                        Icons.photo_camera_outlined,
                        color: Colors.white,
                        size: 44,
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Preparing camera…',
                      style: TextStyle(
                        color: Colors.white60,
                        fontSize: 13,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
