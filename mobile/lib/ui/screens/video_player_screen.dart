import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../core/haptics/app_haptics.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../providers/auth_provider.dart';
import '../../services/supabase_service.dart';
import '../router/app_router.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/loading/skeleton_box.dart';
import '../widgets/modals/post_open_upsell_sheet.dart';
import '../widgets/navigation/spring_page_route.dart';
import '../widgets/primary_button.dart';
import '../widgets/video/handwritten_note_overlay.dart';
import '../widgets/video/video_pre_roll.dart';
import '../widgets/watermark_stamp.dart';
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
    this.capturedAt,
    this.skipPreRoll = false,
    this.capsuleId,
    this.latitude,
    this.longitude,
  });

  final Uint8List mediaBytes;
  final String mimeType;
  final String? note;
  final List<Uint8List> photos;
  final DateTime? capturedAt;
  final bool skipPreRoll;
  final String? capsuleId;

  /// Optional capsule GPS coordinates. When provided (together with
  /// [capturedAt]), the same date + coords watermark shown on the camera
  /// during recording is rendered as an overlay on the playing video.
  final double? latitude;
  final double? longitude;

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  VideoPlayerController? _controller;
  bool _isReady = false;
  bool _videoEnded = false;
  bool _showNote = true;
  bool _showPreRoll = false;
  bool _preRollDone = false;
  bool _markedViewed = false;

  @override
  void initState() {
    super.initState();
    _showPreRoll = !widget.skipPreRoll && widget.capturedAt != null;
    _preRollDone = widget.skipPreRoll || widget.capturedAt == null;
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
      if (_preRollDone) {
        await _startPlayback();
      }
    } catch (e) {
      if (mounted) AppSnackbar.showError(context, e);
    }
  }

  Future<void> _startPlayback() async {
    final controller = _controller;
    if (controller == null) return;
    await controller.play();
    AppHaptics.medium();
    await _markViewedIfNeeded();
    _scheduleNoteHide();
  }

  /// Keeps the note readable: reveal delay + typing time (~42ms/char) plus a
  /// generous dwell so even a full-length note can be read before it fades.
  void _scheduleNoteHide() {
    final note = widget.note;
    if (note == null || note.isEmpty) return;
    final typingMs = 220 + note.length * 42;
    const dwellMs = 6000;
    Future.delayed(Duration(milliseconds: typingMs + dwellMs), () {
      if (mounted) setState(() => _showNote = false);
    });
  }

  Future<void> _markViewedIfNeeded() async {
    if (_markedViewed || widget.capsuleId == null) return;
    final userId = context.read<AuthProvider>().userId;
    if (userId == null) return;
    _markedViewed = true;
    try {
      await SupabaseService.markReceivedCapsuleViewed(
        userId: userId,
        capsuleId: widget.capsuleId!,
      );
    } catch (_) {
      // Non-fatal for playback.
    }
  }

  void _onPreRollComplete() {
    if (!mounted) return;
    setState(() {
      _showPreRoll = false;
      _preRollDone = true;
    });
    _startPlayback();
  }

  void _onVideoTick() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    final v = controller.value;
    if (!_videoEnded && v.position >= v.duration && v.duration > Duration.zero) {
      setState(() => _videoEnded = true);
    }
  }

  Future<void> _replayVideo() async {
    final controller = _controller;
    if (controller == null) return;
    await controller.seekTo(Duration.zero);
    await controller.play();
    if (mounted) setState(() => _videoEnded = false);
  }

  Future<void> _finish() async {
    final result = await PostOpenUpsellSheet.show(context);
    if (!mounted) return;
    if (result == UpsellResult.paywall) {
      await Navigator.of(context).push(
        SpringPageRoute(page: const PaywallScreen()),
      );
      if (!mounted) return;
    }
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
    final showGallery = _videoEnded;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                Expanded(
                  child: Center(
                    child: !_isReady || controller == null
                        ? const SkeletonBox(
                            width: 240,
                            height: 320,
                            borderRadius: 24,
                          )
                        : showGallery
                            ? _UnifiedGallery(
                                controller: controller,
                                photos: widget.photos,
                                onReplayVideo: _replayVideo,
                                capturedAt: widget.capturedAt,
                                latitude: widget.latitude,
                                longitude: widget.longitude,
                              )
                            : _VideoStage(
                                controller: controller,
                                note: widget.note ?? '',
                                showNote: _showNote && _preRollDone,
                                capturedAt: widget.capturedAt,
                                latitude: widget.latitude,
                                longitude: widget.longitude,
                              ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.containerMargin),
                  child: PrimaryButton(label: 'Done', onPressed: _finish),
                ),
              ],
            ),
            if (_showPreRoll && widget.capturedAt != null)
              Positioned.fill(
                child: VideoPreRoll(
                  capturedAt: widget.capturedAt!,
                  onComplete: _onPreRollComplete,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The recording stage during initial playback: video + handwritten note +
/// timestamp watermark rendered in the top-left corner, mirroring the
/// camera's on-screen watermark.
class _VideoStage extends StatelessWidget {
  const _VideoStage({
    required this.controller,
    required this.note,
    required this.showNote,
    required this.capturedAt,
    required this.latitude,
    required this.longitude,
  });

  final VideoPlayerController controller;
  final String note;
  final bool showNote;
  final DateTime? capturedAt;
  final double? latitude;
  final double? longitude;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        GestureDetector(
          onTap: () {
            if (controller.value.isPlaying) {
              controller.pause();
            } else {
              controller.play();
            }
          },
          child: AspectRatio(
            aspectRatio: controller.value.aspectRatio,
            child: Stack(
              children: [
                VideoPlayer(controller),
                if (capturedAt != null)
                  Positioned(
                    top: AppSpacing.sm,
                    left: AppSpacing.md,
                    child: WatermarkStamp(
                      timestamp: capturedAt!,
                    ),
                  ),
              ],
            ),
          ),
        ),
        HandwrittenNoteOverlay(note: note, visible: showNote),
      ],
    );
  }
}

/// Swipeable review of the whole capsule after the initial video watch:
/// page 0 is the video (with a replay affordance + timestamp watermark) so
/// the recipient can restart it any time, followed by every attached photo
/// (including whichever was designated the cover thumbnail). Lets them look
/// at every piece of the memory freely.
class _UnifiedGallery extends StatefulWidget {
  const _UnifiedGallery({
    required this.controller,
    required this.photos,
    required this.onReplayVideo,
    required this.capturedAt,
    required this.latitude,
    required this.longitude,
  });

  final VideoPlayerController controller;
  final List<Uint8List> photos;
  final Future<void> Function() onReplayVideo;
  final DateTime? capturedAt;
  final double? latitude;
  final double? longitude;

  @override
  State<_UnifiedGallery> createState() => _UnifiedGalleryState();
}

class _UnifiedGalleryState extends State<_UnifiedGallery> {
  final _pageController = PageController();
  int _page = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onPageChanged(int i) {
    setState(() => _page = i);
    // Pause the video whenever the user swipes away from its page.
    if (i != 0 && widget.controller.value.isPlaying) {
      widget.controller.pause();
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalPages = 1 + widget.photos.length;
    return Stack(
      alignment: Alignment.bottomCenter,
      children: [
        PageView.builder(
          controller: _pageController,
          itemCount: totalPages,
          onPageChanged: _onPageChanged,
          itemBuilder: (context, i) {
            if (i == 0) {
              return _VideoReplayPage(
                controller: widget.controller,
                onReplay: widget.onReplayVideo,
                capturedAt: widget.capturedAt,
                latitude: widget.latitude,
                longitude: widget.longitude,
              );
            }
            return Image.memory(widget.photos[i - 1], fit: BoxFit.contain);
          },
        ),
        if (totalPages > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < totalPages; i++)
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

/// The video "page" inside the unified gallery: shows the paused video, the
/// timestamp watermark, and — when not playing — a large centered play/replay
/// button. Tapping the video toggles play/pause.
class _VideoReplayPage extends StatefulWidget {
  const _VideoReplayPage({
    required this.controller,
    required this.onReplay,
    required this.capturedAt,
    required this.latitude,
    required this.longitude,
  });

  final VideoPlayerController controller;
  final Future<void> Function() onReplay;
  final DateTime? capturedAt;
  final double? latitude;
  final double? longitude;

  @override
  State<_VideoReplayPage> createState() => _VideoReplayPageState();
}

class _VideoReplayPageState extends State<_VideoReplayPage> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_tick);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_tick);
    super.dispose();
  }

  void _tick() {
    if (mounted) setState(() {});
  }

  Future<void> _handleTap() async {
    final v = widget.controller.value;
    if (!v.isPlaying) {
      if (v.position >= v.duration) {
        await widget.onReplay();
      } else {
        await widget.controller.play();
      }
    } else {
      await widget.controller.pause();
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.controller.value;
    final isPlaying = v.isPlaying;
    final isFinished = v.position >= v.duration && v.duration > Duration.zero;

    return Center(
      child: GestureDetector(
        onTap: _handleTap,
        child: AspectRatio(
          aspectRatio: v.aspectRatio,
          child: Stack(
            alignment: Alignment.center,
            children: [
              VideoPlayer(widget.controller),
              if (widget.capturedAt != null)
                Positioned(
                  top: AppSpacing.sm,
                  left: AppSpacing.md,
                  child: WatermarkStamp(
                    timestamp: widget.capturedAt!,
                  ),
                ),
              if (!isPlaying)
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isFinished ? Icons.replay : Icons.play_arrow,
                    color: Colors.white,
                    size: 40,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
