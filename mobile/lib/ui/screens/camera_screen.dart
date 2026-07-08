import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/permission_gate.dart';
import 'capsule_config_screen.dart';

/// Full-screen video recorder. Wrapped in [PermissionGate] so camera +
/// microphone access is confirmed *before* the [CameraController] is ever
/// initialized, per the cross-cutting permission rule.
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

class _CameraBody extends StatefulWidget {
  const _CameraBody();

  @override
  State<_CameraBody> createState() => _CameraBodyState();
}

class _CameraBodyState extends State<_CameraBody> {
  CameraController? _controller;
  bool _isRecording = false;
  DateTime? _recordingStart;
  Timer? _autoStopTimer;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw Exception('No camera available on this device.');
      }
      final backCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        backCamera,
        ResolutionPreset.medium,
        enableAudio: true,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
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
    try {
      final file = await controller.stopVideoRecording();
      final start = _recordingStart;
      final durationMs = start != null ? DateTime.now().difference(start).inMilliseconds : 0;
      if (mounted) setState(() => _isRecording = false);
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CapsuleConfigScreen(
            videoBytes: bytes,
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
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }
    return Stack(
      alignment: Alignment.bottomCenter,
      children: [
        Positioned.fill(child: CameraPreview(controller)),
        Padding(
          padding: const EdgeInsets.only(bottom: 40),
          child: GestureDetector(
            onTap: _isRecording ? _stopRecording : _startRecording,
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _isRecording ? AppColors.error : AppColors.primary,
                border: Border.all(color: Colors.white, width: 4),
              ),
              child: _isRecording
                  ? const Icon(Icons.stop, color: Colors.white)
                  : null,
            ),
          ),
        ),
      ],
    );
  }
}
