import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/modals/memory_saved_modal.dart';
import '../widgets/primary_button.dart';
import 'home_screen.dart';

/// Plays the decrypted capsule media once the Radar screen unlocks it.
/// Writes [mediaBytes] to a temp file (video_player needs a file/URL, not
/// raw bytes) and disposes the controller on exit.
class VideoPlayerScreen extends StatefulWidget {
  const VideoPlayerScreen({super.key, required this.mediaBytes, required this.mimeType});

  final Uint8List mediaBytes;
  final String mimeType;

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  VideoPlayerController? _controller;
  bool _isReady = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final dir = await getTemporaryDirectory();
      final ext = widget.mimeType.contains('mp4') ? 'mp4' : 'mov';
      final file = File('${dir.path}/capsule_${DateTime.now().millisecondsSinceEpoch}.$ext');
      await file.writeAsBytes(widget.mediaBytes);

      final controller = VideoPlayerController.file(file);
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _isReady = true;
      });
      await controller.play();
    } catch (e) {
      if (mounted) AppSnackbar.showError(context, e);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: !_isReady || controller == null
                    ? const CircularProgressIndicator(color: AppColors.primary)
                    : GestureDetector(
                        onTap: () {
                          setState(() {
                            if (controller.value.isPlaying) {
                              controller.pause();
                            } else {
                              controller.play();
                            }
                          });
                        },
                        child: AspectRatio(
                          aspectRatio: controller.value.aspectRatio,
                          child: VideoPlayer(controller),
                        ),
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.containerMargin),
              child: PrimaryButton(
                label: 'Done',
                onPressed: () async {
                  await MemorySavedModal.show(context);
                  if (!context.mounted) return;
                  // RadarScreen (this screen's predecessor) is always reached
                  // via MainRouter's clipboard-link swap, i.e. it *is* the
                  // root route — there is no HomeScreen already on the stack
                  // to pop back to (`Navigator.popUntil(isFirst)` would be a
                  // no-op here). `pushAndRemoveUntil` guarantees landing on a
                  // fresh Home either way.
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => const HomeScreen()),
                    (route) => false,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
