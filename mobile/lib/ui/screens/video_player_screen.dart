import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../router/app_router.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/modals/post_open_upsell_sheet.dart';
import '../widgets/primary_button.dart';
import 'paywall_screen.dart';

/// Plays the decrypted capsule media once unlocked. Shows the sender's note
/// as an elegant fading overlay, then — after the video ends — lets the
/// recipient swipe through any attached photos. "Done" surfaces the
/// post-open upsell.
class VideoPlayerScreen extends StatefulWidget {
  const VideoPlayerScreen({
    super.key,
    required this.mediaBytes,
    required this.mimeType,
    this.note,
    this.photos = const [],
  });

  final Uint8List mediaBytes;
  final String mimeType;
  final String? note;
  final List<Uint8List> photos;

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  VideoPlayerController? _controller;
  bool _isReady = false;
  bool _videoEnded = false;
  bool _showNote = true;

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
      controller.addListener(_onVideoTick);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _isReady = true;
      });
      await controller.play();
      // Fade the note out a few seconds into playback.
      Future.delayed(const Duration(seconds: 4), () {
        if (mounted) setState(() => _showNote = false);
      });
    } catch (e) {
      if (mounted) AppSnackbar.showError(context, e);
    }
  }

  void _onVideoTick() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    final v = controller.value;
    if (!_videoEnded && v.position >= v.duration && v.duration > Duration.zero) {
      setState(() => _videoEnded = true);
    }
  }

  Future<void> _finish() async {
    final result = await PostOpenUpsellSheet.show(context);
    if (!mounted) return;
    if (result == UpsellResult.paywall) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const PaywallScreen()),
      );
      if (!mounted) return;
    }
    // Reached from the Gallery (a route beneath to pop to) or the recipient-
    // clipboard flow (root). In the latter, enter the app — routing a
    // brand-new recipient through onboarding first.
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      enterAppAfterRecipient(context);
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_onVideoTick);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final showPhotos = _videoEnded && widget.photos.isNotEmpty;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: !_isReady || controller == null
                    ? const CircularProgressIndicator(color: AppColors.primary)
                    : showPhotos
                        ? _PhotoGallery(photos: widget.photos)
                        : Stack(
                            alignment: Alignment.bottomLeft,
                            children: [
                              GestureDetector(
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
                              if (widget.note != null && widget.note!.isNotEmpty)
                                Positioned(
                                  left: AppSpacing.md,
                                  right: AppSpacing.md,
                                  bottom: AppSpacing.md,
                                  child: AnimatedOpacity(
                                    opacity: _showNote ? 1 : 0,
                                    duration: const Duration(milliseconds: 800),
                                    child: Text(
                                      widget.note!,
                                      style: AppTypography.headlineMd.copyWith(
                                        color: Colors.white,
                                        shadows: const [Shadow(color: Colors.black87, blurRadius: 8)],
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.containerMargin),
              child: PrimaryButton(label: 'Done', onPressed: _finish),
            ),
          ],
        ),
      ),
    );
  }
}

/// Swipeable gallery of the capsule's attached photos, shown after the video.
class _PhotoGallery extends StatefulWidget {
  const _PhotoGallery({required this.photos});

  final List<Uint8List> photos;

  @override
  State<_PhotoGallery> createState() => _PhotoGalleryState();
}

class _PhotoGalleryState extends State<_PhotoGallery> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.bottomCenter,
      children: [
        PageView.builder(
          controller: _controller,
          itemCount: widget.photos.length,
          onPageChanged: (i) => setState(() => _page = i),
          itemBuilder: (context, i) => Image.memory(widget.photos[i], fit: BoxFit.contain),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < widget.photos.length; i++)
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i == _page ? AppColors.primary : Colors.white38,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
