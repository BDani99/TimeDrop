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
import '../../providers/vault_provider.dart';
import '../../services/supabase_service.dart';
import '../router/app_router.dart';
import '../utils/route_transition.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/memory/keepsake_card.dart';
import '../widgets/primary_button.dart';
import '../widgets/video/handwritten_note_overlay.dart';
import '../widgets/watermark_stamp.dart';

/// Plays the decrypted capsule media once unlocked. Shows the sender's note
/// as an elegant fading overlay, then — after the video ends — lets the
/// recipient swipe through any attached photos and, last, back to the
/// keepsake card they earned by going there. "Done" hands them over to the
/// Vault.
class VideoPlayerScreen extends StatefulWidget {
  const VideoPlayerScreen({
    super.key,
    required this.mediaBytes,
    required this.mimeType,
    this.note,
    this.photos = const [],
    this.capturedAt,
    this.capsuleId,
    this.latitude,
    this.longitude,
    this.facts,
    this.autoPlay = true,
  });

  final Uint8List mediaBytes;
  final String mimeType;
  final String? note;
  final List<Uint8List> photos;
  final DateTime? capturedAt;
  final String? capsuleId;

  /// Optional capsule GPS coordinates. When provided (together with
  /// [capturedAt]), the same date + coords watermark shown on the camera
  /// during recording is rendered as an overlay on the playing video.
  final double? latitude;
  final double? longitude;

  /// Where, when and how close — the card shown at the end of the unlock.
  /// Given here so the same card stays swipeable after the video and photos,
  /// on this viewing and on every later replay.
  final MemoryFacts? facts;

  /// Whether the video starts on its own.
  ///
  /// True for the first viewing, where the playback *is* the moment the
  /// recipient walked there for. False when the memory is replayed from the
  /// Vault: someone reopening an old drop may well have come for a photo, and
  /// a video that starts talking on its own takes that choice away. With it
  /// off, the screen opens straight into the gallery — video paused on the
  /// first page, photos a swipe away, playback one tap.
  final bool autoPlay;

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

/// Shown while the video file is being written to disk and the controller
/// is initialising. A dark frosted card with a spinner replaces the
/// stark white SkeletonBox on the black background.
class _VideoLoadingPlaceholder extends StatelessWidget {
  const _VideoLoadingPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 240,
          height: 320,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(24),
          ),
          child: const Center(
            child: CircularProgressIndicator(
              color: Colors.white38,
              strokeWidth: 2,
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Loading memory…',
          style: TextStyle(color: Colors.white38, fontSize: 13),
        ),
      ],
    );
  }
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  VideoPlayerController? _controller;
  bool _isReady = false;

  /// Whether the swipeable gallery (video page + photos + keepsake) is showing
  /// instead of the single full-bleed playback stage. Set when the first watch
  /// finishes — or straight away on a replay, which never has a first watch.
  bool _showGallery = false;
  bool _showNote = true;
  bool _markedViewed = false;

  @override
  void initState() {
    super.initState();
    // Defer controller init until after the route is fully settled. Creating a
    // VideoPlayer under a fading / snapshotting route leaves the Android
    // texture detached — the UI looks ready but playback never starts.
    WidgetsBinding.instance.addPostFrameCallback((_) => _waitForRouteThenInit());
  }

  Future<void> _waitForRouteThenInit() async {
    if (!mounted) return;
    // No timeout here: a detached texture is worse than a late start, so this
    // one genuinely wants to wait for the transition rather than give up on it.
    await waitForRouteTransition(context, timeout: const Duration(seconds: 2));
    if (!mounted) return;
    await _init();
  }

  Future<void> _init() async {
    try {
      if (widget.mediaBytes.isEmpty) {
        throw StateError('Memory media is empty.');
      }
      final dir = await getTemporaryDirectory();
      final ext = widget.mimeType.contains('mp4')
          ? 'mp4'
          : widget.mimeType.contains('webm')
              ? 'webm'
              : 'mov';
      final file = File(
        '${dir.path}/capsule_${DateTime.now().millisecondsSinceEpoch}.$ext',
      );
      await file.writeAsBytes(widget.mediaBytes, flush: true);

      final controller = VideoPlayerController.file(file);
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      controller.addListener(_onVideoTick);
      setState(() {
        _controller = controller;
        _isReady = true;
        // A replay has no first watch to wait out — the gallery is the whole
        // screen from the start, with the video paused on its first page.
        _showGallery = !widget.autoPlay;
      });
      // Written down whether or not anything plays: opening the memory is what
      // "viewed" means, and a replay should still refresh when that last was.
      await _markViewedIfNeeded();
      if (widget.autoPlay) await _startPlayback();
    } catch (e) {
      if (mounted) AppSnackbar.showError(context, e);
    }
  }

  Future<void> _startPlayback() async {
    final controller = _controller;
    if (controller == null) return;
    await controller.play();
    AppHaptics.medium();
    _scheduleNoteHide();
  }

  /// Keeps the note readable: reveal delay + typing time (~42ms/char) plus a
  /// generous dwell so even a full-length note can be read before it fades.
  void _scheduleNoteHide() {
    final note = widget.note;
    if (note == null || note.isEmpty) return;
    final typingMs = 220 + note.length * 42;
    const dwellMs = 9000;
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
        // Only known on the unlock itself. Written down now because the
        // keepsake card has to be able to say it again years later, and the
        // radar's reading is gone the moment this screen appears.
        unlockDistanceMeters: widget.facts?.distanceMeters,
      );
    } catch (_) {
      // Non-fatal for playback.
    }
  }

  void _onVideoTick() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    final v = controller.value;
    if (!_showGallery && v.position >= v.duration && v.duration > Duration.zero) {
      setState(() => _showGallery = true);
    }
  }

  Future<void> _replayVideo() async {
    final controller = _controller;
    if (controller == null) return;
    await controller.seekTo(Duration.zero);
    await controller.play();
  }

  /// "Done". Nothing is sold here any more — a paywall thrown up in the second
  /// after a memory ends spends the best moment of the app on an ask. The
  /// recipient goes to the Vault instead, where the memory they just watched is
  /// waiting for them and the offer sits quietly underneath it.
  void _finish() {
    // A replay launched from the Vault simply goes back to it; only a memory
    // opened in the field earns the arrival highlight.
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      return;
    }
    context.read<VaultProvider>().markJustOpened(widget.capsuleId);
    enterAppAfterRecipient(context, landOnVault: true);
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
                        ? const _VideoLoadingPlaceholder()
                        : _showGallery
                            ? _UnifiedGallery(
                                controller: controller,
                                photos: widget.photos,
                                onReplayVideo: _replayVideo,
                                note: widget.note,
                                capturedAt: widget.capturedAt,
                                latitude: widget.latitude,
                                longitude: widget.longitude,
                                facts: widget.facts,
                              )
                            : _VideoStage(
                                controller: controller,
                                note: widget.note ?? '',
                                showNote: _showNote,
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
                      latitude: latitude,
                      longitude: longitude,
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
    required this.note,
    required this.capturedAt,
    required this.latitude,
    required this.longitude,
    required this.facts,
  });

  final VideoPlayerController controller;
  final List<Uint8List> photos;
  final Future<void> Function() onReplayVideo;

  /// The sender's note. Shown over the paused video page, because a replay
  /// opens straight into the gallery and would otherwise never show it — the
  /// note used to live only on the first watch's playback stage.
  final String? note;
  final DateTime? capturedAt;
  final double? latitude;
  final double? longitude;

  /// When present, the keepsake card becomes the last page.
  final MemoryFacts? facts;

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
    final facts = widget.facts;
    // Video, then every photo, then — last — the keepsake card. It goes at the
    // end because that is where it was earned: after everything the sender
    // left, the record of the recipient having gone and stood there.
    final keepsakeIndex = facts == null ? -1 : 1 + widget.photos.length;
    final totalPages = 1 + widget.photos.length + (facts == null ? 0 : 1);

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
                note: widget.note,
                capturedAt: widget.capturedAt,
                latitude: widget.latitude,
                longitude: widget.longitude,
              );
            }
            if (i == keepsakeIndex) {
              return KeepsakeCard(facts: facts!);
            }
            return Stack(
              fit: StackFit.expand,
              children: [
                Image.memory(widget.photos[i - 1], fit: BoxFit.contain),
                if (widget.capturedAt != null)
                  Positioned(
                    top: AppSpacing.sm,
                    left: AppSpacing.md,
                    child: WatermarkStamp(
                      timestamp: widget.capturedAt!,
                      latitude: widget.latitude,
                      longitude: widget.longitude,
                    ),
                  ),
              ],
            );
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
                      // The keepsake page is sand-coloured, every other page is
                      // a photo or video on black. White dots would vanish on
                      // the one page that has no image behind them.
                      color: i == _page
                          ? AppColors.primary
                          : (_page == keepsakeIndex
                              ? AppColors.onSurfaceVariant.withValues(alpha: 0.35)
                              : Colors.white38),
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
/// timestamp watermark, the sender's note while nothing is playing, and — when
/// not playing — a large centered play/replay button. Tapping the video toggles
/// play/pause.
class _VideoReplayPage extends StatefulWidget {
  const _VideoReplayPage({
    required this.controller,
    required this.onReplay,
    required this.note,
    required this.capturedAt,
    required this.latitude,
    required this.longitude,
  });

  final VideoPlayerController controller;
  final Future<void> Function() onReplay;
  final String? note;
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
    final note = widget.note ?? '';

    return Stack(
      alignment: Alignment.center,
      children: [
        Center(
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
                        latitude: widget.latitude,
                        longitude: widget.longitude,
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
        ),
        // The note is what the sender wrote, so it greets a replay the same way
        // it greeted the first watch — and gets out of the way the moment the
        // video starts, rather than sitting on top of it.
        HandwrittenNoteOverlay(note: note, visible: !isPlaying),
      ],
    );
  }
}
