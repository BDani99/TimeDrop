import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../../core/haptics/app_haptics.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../providers/settings_provider.dart';
import '../../services/photo_processing_service.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/glass/glass_panel.dart';
import '../widgets/permission_gate.dart';
import '../widgets/watermark_stamp.dart';

/// In-app still camera for attaching photos to a drop — same full-screen
/// experience as [CameraScreen] (video), without opening the OS camera app.
///
/// Returns the processed JPEG path via [Navigator.pop], or null if cancelled.
class DropPhotoCameraScreen extends StatelessWidget {
  const DropPhotoCameraScreen({super.key});

  static Future<bool> _requestPermissions() async {
    final status = await Permission.camera.request();
    return status.isGranted;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: PermissionGate(
        requestPermission: _requestPermissions,
        deniedMessage: 'Camera access is required to take a photo.',
        child: const _DropPhotoCameraBody(),
      ),
    );
  }
}

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

class _DropPhotoCameraBody extends StatefulWidget {
  const _DropPhotoCameraBody();

  @override
  State<_DropPhotoCameraBody> createState() => _DropPhotoCameraBodyState();
}

class _DropPhotoCameraBodyState extends State<_DropPhotoCameraBody>
    with SingleTickerProviderStateMixin {
  CameraController? _controller;
  List<CameraDescription> _cameras = const [];
  CameraLensDirection _lensDirection = CameraLensDirection.front;
  _FlashState _flash = _FlashState.off;

  bool _isSwitching = false;
  bool _isCapturing = false;

  /// Set after shutter — review before returning to the drop config screen.
  String? _previewPath;

  double _zoomMin = 1.0;
  double _zoomMax = 1.0;
  double _zoom = 1.0;

  /// Preview area aspect (width ÷ height) — used so the saved crop matches
  /// what [BoxFit.cover] shows on screen.
  double _viewportAspect = 9 / 16;

  late final AnimationController _lensSwitchController;

  @override
  void initState() {
    super.initState();
    _lensSwitchController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _initCamera();
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
      enableAudio: false,
    );
    await controller.initialize();
    try {
      await controller.setFlashMode(_flash.mode);
    } catch (_) {
      _flash = _FlashState.off;
    }
    if (!mounted) {
      await controller.dispose();
      return;
    }
    await _initZoom(controller);
    if (!mounted) {
      await controller.dispose();
      return;
    }
    setState(() {
      _controller = controller;
      _lensDirection = camera.lensDirection;
    });
  }

  Future<void> _initZoom(CameraController controller) async {
    try {
      final min = await controller.getMinZoomLevel();
      final max = await controller.getMaxZoomLevel();
      final start = 1.0.clamp(min, max);
      await controller.setZoomLevel(start);
      _zoomMin = min;
      _zoomMax = max;
      _zoom = start;
    } catch (_) {
      _zoomMin = 1.0;
      _zoomMax = 1.0;
      _zoom = 1.0;
    }
  }

  Future<void> _setZoom(double value) async {
    final controller = _controller;
    if (controller == null || _isCapturing) return;
    final clamped = value.clamp(_zoomMin, _zoomMax);
    try {
      await controller.setZoomLevel(clamped);
      if (mounted) setState(() => _zoom = clamped);
    } catch (_) {
      // Some devices reject intermediate zoom steps — ignore.
    }
  }

  static const List<double> _zoomPresets = [0.5, 1.0, 2.0];

  List<double> _availableZoomPresets() {
    return _zoomPresets
        .where((p) => p >= _zoomMin - 0.01 && p <= _zoomMax + 0.01)
        .toList(growable: false);
  }

  double? _activeZoomPreset() {
    double? closest;
    var closestDistance = double.infinity;
    for (final preset in _availableZoomPresets()) {
      final distance = (_zoom - preset).abs();
      if (distance < closestDistance) {
        closestDistance = distance;
        closest = preset;
      }
    }
    return closestDistance <= 0.2 ? closest : null;
  }

  Future<void> _selectZoomPreset(double preset) async {
    await AppHaptics.light();
    await _setZoom(preset);
  }

  Future<void> _switchCamera() async {
    if (_isSwitching || _isCapturing || _cameras.length < 2) return;
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

  Future<void> _capturePhoto() async {
    final controller = _controller;
    if (controller == null || _isCapturing) return;
    final mirror = context.read<SettingsProvider>().mirrorDropPhotos;
    final viewportAspect = _viewportAspect;
    setState(() => _isCapturing = true);
    try {
      await AppHaptics.medium();
      final file = await controller.takePicture();
      final processed = await PhotoProcessingService.processCameraCapture(
        sourcePath: file.path,
        mirror: mirror,
        viewportAspectWidthOverHeight: viewportAspect,
      );
      if (!mounted) return;
      setState(() => _previewPath = processed);
    } catch (e) {
      if (mounted) AppSnackbar.showError(context, e);
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  void _retakePhoto() {
    setState(() => _previewPath = null);
  }

  void _confirmPhoto() {
    final path = _previewPath;
    if (path == null) return;
    Navigator.of(context).pop(path);
  }

  @override
  void dispose() {
    _lensSwitchController.dispose();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final preview = _previewPath;
    if (preview != null) {
      return _PhotoPreviewReview(
        path: preview,
        onRetake: _retakePhoto,
        onConfirm: _confirmPhoto,
        onCancel: () => Navigator.of(context).pop(),
      );
    }

    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _isSwitching) {
      return const _PhotoCameraInitPlaceholder();
    }

    final flashAvailable = _lensDirection == CameraLensDirection.back;
    final zoomPresets = _availableZoomPresets();
    final zoomEnabled = zoomPresets.length >= 2;

    return Stack(
      children: [
        Positioned.fill(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final aspect = constraints.maxWidth / constraints.maxHeight;
              if ((aspect - _viewportAspect).abs() > 0.001) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && (aspect - _viewportAspect).abs() > 0.001) {
                    setState(() => _viewportAspect = aspect);
                  }
                });
              }
              return AnimatedBuilder(
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
              );
            },
          ),
        ),
        SafeArea(
          child: Stack(
            children: [
              Positioned(
                top: AppSpacing.sm,
                left: AppSpacing.md,
                child: WatermarkStamp(timestamp: DateTime.now()),
              ),
              Positioned(
                top: AppSpacing.xs,
                right: AppSpacing.sm,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: _isCapturing ? null : () => Navigator.of(context).pop(),
                ),
              ),
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
                      if (zoomEnabled) ...[
                        _ZoomPresetBar(
                          presets: zoomPresets,
                          selected: _activeZoomPreset(),
                          enabled: !_isCapturing,
                          onPresetSelected: _selectZoomPreset,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                      ],
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
                                        onTap: _isCapturing ? null : _cycleFlash,
                                      ),
                                    ),
                                  )
                                : null,
                          ),
                          GlassPanel(
                            padding: const EdgeInsets.all(6),
                            borderRadius: BorderRadius.circular(999),
                            opacity: 0.55,
                            child: _ShutterButton(
                              busy: _isCapturing,
                              onTap: _capturePhoto,
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
                                        onTap: _isCapturing ? null : _switchCamera,
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

/// Full-screen preview after capture — ✓ keeps the photo, ✗ takes another.
class _PhotoPreviewReview extends StatelessWidget {
  const _PhotoPreviewReview({
    required this.path,
    required this.onRetake,
    required this.onConfirm,
    required this.onCancel,
  });

  final String path;
  final VoidCallback onRetake;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.file(File(path), fit: BoxFit.cover),
        SafeArea(
          child: Stack(
            children: [
              Positioned(
                top: AppSpacing.xs,
                right: AppSpacing.sm,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: onCancel,
                ),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    0,
                    AppSpacing.lg,
                    40,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Keep this photo?',
                        textAlign: TextAlign.center,
                        style: AppTypography.labelMd.copyWith(color: Colors.white70),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _ReviewActionButton(
                            icon: Icons.close,
                            label: 'Retake',
                            onTap: onRetake,
                          ),
                          const SizedBox(width: AppSpacing.xl),
                          _ReviewActionButton(
                            icon: Icons.check,
                            label: 'Use photo',
                            primary: true,
                            onTap: onConfirm,
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

class _ReviewActionButton extends StatelessWidget {
  const _ReviewActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: primary ? AppColors.primary : Colors.black45,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 64,
              height: 64,
              child: Icon(icon, color: Colors.white, size: primary ? 32 : 28),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          label,
          style: AppTypography.labelSm.copyWith(color: Colors.white70),
        ),
      ],
    );
  }
}

/// Samsung-style preset zoom — .5 / 1 / 2 chips above the shutter.
class _ZoomPresetBar extends StatelessWidget {
  const _ZoomPresetBar({
    required this.presets,
    required this.selected,
    required this.enabled,
    required this.onPresetSelected,
  });

  final List<double> presets;
  final double? selected;
  final bool enabled;
  final ValueChanged<double> onPresetSelected;

  static String _label(double preset) {
    if (preset == 0.5) return '.5';
    if (preset == 1.0) return '1';
    return preset.toStringAsFixed(0);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < presets.length; i++) ...[
          if (i > 0) const SizedBox(width: 18),
          _ZoomPresetChip(
            label: _label(presets[i]),
            selected: selected == presets[i],
            enabled: enabled,
            onTap: () => onPresetSelected(presets[i]),
          ),
        ],
      ],
    );
  }
}

class _ZoomPresetChip extends StatelessWidget {
  const _ZoomPresetChip({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        width: selected ? 38 : 30,
        height: selected ? 38 : 30,
        alignment: Alignment.center,
        decoration: selected
            ? BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.94),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.28),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              )
            : null,
        child: Text(
          label,
          style: AppTypography.labelSm.copyWith(
            fontSize: selected ? 13 : 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected
                ? Colors.black87
                : Colors.white.withValues(alpha: enabled ? 0.72 : 0.35),
            height: 1,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}

class _ShutterButton extends StatelessWidget {
  const _ShutterButton({required this.busy, required this.onTap});

  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: busy ? null : onTap,
      child: SizedBox(
        width: 84,
        height: 84,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 4),
              ),
            ),
            if (busy)
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            else
              Container(
                width: 68,
                height: 68,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary,
                ),
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

class _PhotoCameraInitPlaceholder extends StatefulWidget {
  const _PhotoCameraInitPlaceholder();

  @override
  State<_PhotoCameraInitPlaceholder> createState() => _PhotoCameraInitPlaceholderState();
}

class _PhotoCameraInitPlaceholderState extends State<_PhotoCameraInitPlaceholder>
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
