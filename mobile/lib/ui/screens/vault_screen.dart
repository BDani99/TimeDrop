import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../models/received_capsule_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/payment_provider.dart';
import '../../providers/vault_provider.dart';
import '../../services/clipboard_service.dart';
import '../../services/media_cache_service.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/loading/skeleton_box.dart';
import '../widgets/vault/vault_calendar_view.dart';
import 'memory_detail_screen.dart';
import '../widgets/countdown_timer.dart';
import '../widgets/primary_button.dart';
import 'gift_received_screen.dart';
import 'paywall_screen.dart';
import 'radar_screen.dart';
import 'video_player_screen.dart';
import '../widgets/navigation/spring_page_route.dart';

enum VaultView { timeline, map, calendar }

/// The recipient's "Vault": an immersive timeline / map of received memories,
/// with manual redemption, progressive-auth protection, and an upsell hook.
class VaultScreen extends StatefulWidget {
  const VaultScreen({super.key});

  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen> {
  VaultView _view = VaultView.timeline;
  bool _isReopening = false;
  bool _thumbnailsWarmed = false;
  bool _started = false;

  /// Fully-resolved unlocked-card previews (cover bytes + note text) keyed by
  /// `capsuleId`. Populated by `_warmThumbnails` before the timeline renders
  /// so cards paint fully-populated instead of streaming in one-by-one.
  final Map<String, _UnlockedPreview> _previews = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;

    // If Home already hydrated the vault, paint immediately — don't flash a
    // skeleton during the route transition (main Home↔Vault micro-lag source).
    final vault = context.read<VaultProvider>();
    if (vault.receivedCapsules.isNotEmpty) {
      _thumbnailsWarmed = true;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  /// Reads every unlocked card's cover photo + cached note in parallel, then
  /// `precacheImage`s each cover so the first paint is instant.
  Future<void> _warmThumbnails(List<ReceivedCapsuleModel> items) async {
    final results = await Future.wait([
      for (final item in items.where((c) => c.isViewed))
        () async {
          final cover = await MediaCacheService.coverPhoto(item.capsuleId);
          final note = await MediaCacheService.noteFor(item.capsuleId);
          if (cover != null && mounted) {
            await precacheImage(MemoryImage(cover), context);
          }
          return MapEntry(
            item.capsuleId,
            _UnlockedPreview(cover: cover, note: note),
          );
        }(),
    ]);
    if (!mounted) return;
    _previews
      ..clear()
      ..addEntries(results);
  }

  String? get _userId => context.read<AuthProvider>().userId;

  Future<void> _waitForIncomingTransition() async {
    final animation = ModalRoute.of(context)?.animation;
    if (animation == null || animation.isCompleted) return;

    final done = Completer<void>();
    void listener(AnimationStatus status) {
      if (status == AnimationStatus.completed ||
          status == AnimationStatus.dismissed) {
        animation.removeStatusListener(listener);
        if (!done.isCompleted) done.complete();
      }
    }

    animation.addStatusListener(listener);
    // Safety if the status never fires (e.g. interrupted).
    await Future.any([
      done.future,
      Future<void>.delayed(const Duration(milliseconds: 400)),
    ]);
    animation.removeStatusListener(listener);
  }

  Future<void> _load() async {
    final userId = _userId;
    if (userId == null) return;
    final provider = context.read<VaultProvider>();
    final hadCache = provider.receivedCapsules.isNotEmpty;

    // Only blank the UI when we have nothing to show yet.
    if (!hadCache && mounted) {
      setState(() => _thumbnailsWarmed = false);
    }

    try {
      await provider.load(userId, silent: hadCache);
      if (!mounted) return;
      await _waitForIncomingTransition();
      if (!mounted) return;
      await _warmThumbnails(provider.receivedCapsules);
    } catch (e) {
      if (mounted) AppSnackbar.showError(context, e);
    } finally {
      if (mounted) setState(() => _thumbnailsWarmed = true);
    }
  }

  void _openRadar(ReceivedCapsuleModel item) {
    if (!item.hasKey) {
      AppSnackbar.showMessage(
        context,
        'You need the full link to open this — ask the sender to resend it.',
      );
      return;
    }
    Navigator.push(
      context,
      SpringPageRoute(
        page: RadarScreen(
          shareId: item.shareId,
          encryptionKey: item.encryptionKey!,
          fromName: item.fromName,
        ),
      ),
    );
  }

  /// Waiting drops open the gift intro (countdown only). Ready drops go to Radar.
  void _openReceived(ReceivedCapsuleModel item) {
    if (!item.hasKey) {
      AppSnackbar.showMessage(
        context,
        'You need the full link to open this — ask the sender to resend it.',
      );
      return;
    }
    if (item.isUnlockTimeReached) {
      _openRadar(item);
      return;
    }
    Navigator.push(
      context,
      SpringPageRoute(
        page: GiftReceivedScreen(
          shareId: item.shareId,
          encryptionKey: item.encryptionKey!,
          fromName: item.fromName,
        ),
      ),
    ).then((_) {
      if (mounted) _load();
    });
  }

  void _openDetail(ReceivedCapsuleModel item, {required String actionLabel, required VoidCallback onAction}) {
    Navigator.push(
      context,
      SpringPageRoute(
        page: MemoryDetailScreen(
          item: item,
          primaryLabel: actionLabel,
          onPrimaryAction: () {
            Navigator.pop(context);
            onAction();
          },
        ),
      ),
    );
  }

  Future<void> _reopen(ReceivedCapsuleModel item) async {
    if (_isReopening) return;
    setState(() => _isReopening = true);
    try {
      final content = await context.read<VaultProvider>().reopen(item);
      if (!mounted) return;
      Navigator.push(
        context,
        SpringPageRoute(
          page: VideoPlayerScreen(
            mediaBytes: content.mediaBytes,
            mimeType: content.mimeType,
            note: content.note,
            photos: content.photos,
            skipPreRoll: true,
            capsuleId: item.capsuleId,
            capturedAt: item.capsuleCreatedAt ?? item.unlockTime,
            latitude: item.latitude,
            longitude: item.longitude,
          ),
        ),
      );
    } catch (e) {
      if (mounted) AppSnackbar.showError(context, e);
    } finally {
      if (mounted) setState(() => _isReopening = false);
    }
  }

  Future<void> _showRedeemSheet() async {
    // Show the sheet immediately — clipboard prefill happens inside initState
    // of the sheet so the tap response is instant.
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.35),
      builder: (_) => _RedeemSheet(onSubmit: _submitCode),
    );
  }

  Future<void> _submitCode(String input) async {
    final userId = _userId;
    if (userId == null) return;
    final link = await context.read<VaultProvider>().submitCode(input, userId: userId);
    if (!mounted) return;
    Navigator.of(context).pop(); // close the sheet
    if (link != null) {
      Navigator.push(
        context,
        SpringPageRoute(
          page: GiftReceivedScreen(
            shareId: link.shareId,
            encryptionKey: link.encryptionKey,
            fromName: link.fromName,
          ),
        ),
      ).then((_) {
        if (mounted) _load();
      });
    } else {
      AppSnackbar.showSuccess(context, 'Added to your vault — waiting to unlock.');
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final vault = context.watch<VaultProvider>();
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('The Vault'),
        actions: [
          IconButton(
            icon: const Icon(Icons.vpn_key_outlined),
            tooltip: 'Redeem a drop',
            onPressed: _showRedeemSheet,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: SegmentedButton<VaultView>(
              segments: const [
                ButtonSegment(
                  value: VaultView.timeline,
                  label: Text('Timeline'),
                  icon: Icon(Icons.view_agenda_outlined),
                ),
                ButtonSegment(
                  value: VaultView.map,
                  label: Text('Map'),
                  icon: Icon(Icons.map_outlined),
                ),
                ButtonSegment(
                  value: VaultView.calendar,
                  label: Text('Calendar'),
                  icon: Icon(Icons.calendar_month_outlined),
                ),
              ],
              selected: {_view},
              onSelectionChanged: (s) => setState(() => _view = s.first),
            ),
          ),
        ),
      ),
      body: !_thumbnailsWarmed
          ? const _VaultLoadingSkeleton()
          : IndexedStack(
              index: _view.index,
              sizing: StackFit.expand,
              children: [
                _TimelineView(
                  vault: vault,
                  isReopening: _isReopening,
                  onRefresh: _load,
                  onOpenReceived: _openReceived,
                  onReopen: _reopen,
                  onOpenDetail: _openDetail,
                  previews: _previews,
                ),
                _MapView(
                  vault: vault,
                  onOpenReceived: _openReceived,
                  onReopen: _reopen,
                ),
                VaultCalendarView(
                  items: vault.receivedCapsules,
                  onSelect: (ReceivedCapsuleModel item) {
                    if (item.isViewed) {
                      _reopen(item);
                    } else if (item.hasKey) {
                      _openReceived(item);
                    } else {
                      _openDetail(
                        item,
                        actionLabel: 'Close',
                        onAction: () {},
                      );
                    }
                  },
                ),
              ],
            ),
    );
  }
}

/// Full-screen loading state — one skeleton per capsule slot — shown while
/// the first `load()` is in flight AND while cover thumbnails are being
/// pre-cached, so cards don't pop in one after another.
class _VaultLoadingSkeleton extends StatelessWidget {
  const _VaultLoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.containerMargin),
      children: const [
        SkeletonBox(width: 200, height: 24),
        SizedBox(height: AppSpacing.md),
        SkeletonMemoryCard(),
        SizedBox(height: AppSpacing.sm),
        SkeletonMemoryCard(),
        SizedBox(height: AppSpacing.sm),
        SkeletonMemoryCard(),
      ],
    );
  }
}

class _TimelineView extends StatelessWidget {
  const _TimelineView({
    required this.vault,
    required this.isReopening,
    required this.onRefresh,
    required this.onOpenReceived,
    required this.onReopen,
    required this.onOpenDetail,
    required this.previews,
  });

  final VaultProvider vault;
  final bool isReopening;
  final Future<void> Function() onRefresh;
  final void Function(ReceivedCapsuleModel) onOpenReceived;
  final void Function(ReceivedCapsuleModel) onReopen;
  final void Function(ReceivedCapsuleModel, {required String actionLabel, required VoidCallback onAction}) onOpenDetail;
  final Map<String, _UnlockedPreview> previews;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final isPremium = context.watch<PaymentProvider>().isPremium;
    final showHighStakes = !auth.isLinked && vault.hasHighStakesCapsule;

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.containerMargin),
        children: [
          if (vault.unlockedCount > 0) ...[
            _StatHeader(moments: vault.unlockedCount, cities: vault.cityCount),
            const SizedBox(height: AppSpacing.md),
          ],
          if (showHighStakes) ...[
            const _HighStakesBanner(),
            const SizedBox(height: AppSpacing.md),
          ],
          if (vault.isLoading && vault.receivedCapsules.isEmpty)
            const SkeletonMemoryCard(),
          if (vault.ready.isNotEmpty) ...[
            _SectionLabel('Ready to open'),
            for (final item in vault.ready) ...[
              _ReadyCard(
                item: item,
                onTap: () => onOpenReceived(item),
                onLongPress: () => onOpenDetail(
                  item,
                  actionLabel: 'Go unlock',
                  onAction: () => onOpenReceived(item),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            const SizedBox(height: AppSpacing.md),
          ],
          if (vault.waiting.isNotEmpty) ...[
            _SectionLabel('Waiting'),
            for (final item in vault.waiting) ...[
              _WaitingCard(
                item: item,
                // Waiting + key → gift intro (countdown). Ready uses radar.
                onTap: item.hasKey ? () => onOpenReceived(item) : null,
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            const SizedBox(height: AppSpacing.md),
          ],
          if (vault.unlocked.isNotEmpty) ...[
            _SectionLabel('Unlocked'),
            for (final item in vault.unlocked) ...[
              _UnlockedCard(
                item: item,
                preview: previews[item.capsuleId] ?? const _UnlockedPreview(),
                isBusy: isReopening,
                onTap: () => onReopen(item),
                onLongPress: () => onOpenDetail(
                  item,
                  actionLabel: 'Replay',
                  onAction: () => onReopen(item),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
          ],
          if (!vault.isLoading &&
              vault.ready.isEmpty &&
              vault.waiting.isEmpty &&
              vault.unlocked.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
              child: Text(
                'Your vault is empty — memories others send you will appear here.',
                textAlign: TextAlign.center,
                style: AppTypography.bodyMd.copyWith(color: AppColors.onSurfaceVariant),
              ),
            ),
          if (!isPremium) ...[
            const SizedBox(height: AppSpacing.md),
            const _FreemiumBanner(),
          ],
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Text(text, style: AppTypography.headlineMd),
    );
  }
}

class _StatHeader extends StatelessWidget {
  const _StatHeader({required this.moments, required this.cities});
  final int moments;
  final int cities;

  @override
  Widget build(BuildContext context) {
    final cityPart = cities > 0
        ? ' in $cities ${cities == 1 ? 'city' : 'cities'}'
        : '';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.secondaryContainer,
        borderRadius: AppRadii.mdRadius,
      ),
      child: Text(
        'You have unlocked $moments ${moments == 1 ? 'moment' : 'moments'}$cityPart.',
        style: AppTypography.bodyMd.copyWith(color: AppColors.onSecondaryContainer),
      ),
    );
  }
}

class _HighStakesBanner extends StatelessWidget {
  const _HighStakesBanner();

  Future<void> _link(BuildContext context, Future<void> Function() action) async {
    try {
      await action();
      if (context.mounted) AppSnackbar.showSuccess(context, 'Account linked.');
    } catch (e) {
      if (context.mounted) AppSnackbar.showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.errorContainer,
        borderRadius: AppRadii.mdRadius,
        border: Border.all(color: AppColors.error.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.shield_outlined, color: AppColors.onErrorContainer, size: 20),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Unregistered Vault',
                  style: AppTypography.labelMd.copyWith(color: AppColors.onErrorContainer),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'If you lose your phone, these memories are gone forever.',
            style: AppTypography.bodyMd.copyWith(color: AppColors.onErrorContainer),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: PrimaryButton(
                  label: 'Continue with Apple',
                  onPressed: () => _link(context, () => context.read<AuthProvider>().linkApple()),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _link(context, () => context.read<AuthProvider>().linkGoogle()),
                  child: const Text('Google'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FreemiumBanner extends StatelessWidget {
  const _FreemiumBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primaryContainer, AppColors.primary],
        ),
        borderRadius: AppRadii.lgRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Start your own timeline.',
            style: AppTypography.headlineMd.copyWith(color: Colors.white),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Leave a mark on the world.',
            style: AppTypography.bodyMd.copyWith(color: Colors.white70),
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white70),
            ),
            onPressed: () => Navigator.push(
              context,
              SpringPageRoute(page: const PaywallScreen()),
            ),
            child: const Text('Unlock Lifetime Access'),
          ),
        ],
      ),
    );
  }
}

/// Ready to open: brighter, gently "breathing", tappable → Radar.
class _ReadyCard extends StatefulWidget {
  const _ReadyCard({required this.item, required this.onTap, this.onLongPress});
  final ReceivedCapsuleModel item;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  State<_ReadyCard> createState() => _ReadyCardState();
}

class _ReadyCardState extends State<_ReadyCard> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_c.value);
        return Transform.scale(scale: 1 + t * 0.015, child: child);
      },
      child: InkWell(
        borderRadius: AppRadii.mdRadius,
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.primaryContainer, AppColors.primary],
            ),
            borderRadius: AppRadii.mdRadius,
          ),
          child: Row(
            children: [
              const Icon(Icons.explore_outlined, color: Colors.white),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.item.senderLabel,
                      style: AppTypography.labelMd.copyWith(color: Colors.white),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Ready to discover. Tap to open Radar.',
                      style: AppTypography.labelSm.copyWith(color: Colors.white70),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}

/// Waiting: frosted / locked look, no content, sender + city + countdown.
/// Tappable (when the full link is held) to reopen the blurred radar.
class _WaitingCard extends StatelessWidget {
  const _WaitingCard({required this.item, this.onTap});
  final ReceivedCapsuleModel item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: AppRadii.mdRadius,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerHigh.withValues(alpha: 0.7),
          borderRadius: AppRadii.mdRadius,
          border: Border.all(color: AppColors.outlineVariant),
        ),
        child: Row(
          children: [
            Icon(
              item.hasKey ? Icons.lock_outline : Icons.link_off,
              color: AppColors.onSurfaceVariant,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.senderLabel, style: AppTypography.labelMd),
                  const SizedBox(height: 2),
                  if (!item.hasKey)
                    Text(
                      'Missing the full link',
                      style: AppTypography.labelSm.copyWith(color: AppColors.error),
                    )
                  else
                    DefaultTextStyle(
                      style: AppTypography.labelSm,
                      child: CountdownTimer(target: item.unlockTime),
                    ),
                ],
              ),
            ),
            if (item.hasKey)
              const Icon(Icons.chevron_right, color: AppColors.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

/// Preloaded assets used to render an [_UnlockedCard] without an async gap.
class _UnlockedPreview {
  const _UnlockedPreview({this.cover, this.note});
  final Uint8List? cover;
  final String? note;
}

/// Unlocked: cached cover thumbnail + date + city + note preview, tap → play.
/// Renders synchronously from a [_UnlockedPreview] populated by the parent
/// screen before the timeline is built.
class _UnlockedCard extends StatelessWidget {
  const _UnlockedCard({
    required this.item,
    required this.preview,
    required this.isBusy,
    required this.onTap,
    this.onLongPress,
  });
  final ReceivedCapsuleModel item;
  final _UnlockedPreview preview;
  final bool isBusy;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  String _date() {
    final d = item.unlockTime.toLocal();
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final cover = preview.cover;
    final note = preview.note;
    return InkWell(
      borderRadius: AppRadii.mdRadius,
      onTap: isBusy ? null : onTap,
      onLongPress: isBusy ? null : onLongPress,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: AppRadii.mdRadius,
          border: Border.all(color: AppColors.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: [
            SizedBox(
              width: 92,
              height: 92,
              child: cover != null
                  ? Image.memory(cover, fit: BoxFit.cover, gaplessPlayback: true)
                  : Container(
                      color: AppColors.surfaceContainerHigh,
                      child: const Icon(Icons.play_circle_outline,
                          color: AppColors.primary, size: 32),
                    ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      item.city != null && item.city!.isNotEmpty
                          ? '${_date()} · ${item.city}'
                          : _date(),
                      style: AppTypography.labelMd,
                    ),
                    if (note != null && note.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        note,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.labelSm
                            .copyWith(color: AppColors.onSurfaceVariant),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (isBusy)
              const Padding(
                padding: EdgeInsets.only(right: AppSpacing.sm),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Keeps the FlutterMap alive across VaultView switches (via IndexedStack) so
/// tiles are only fetched once. Also renders a warm placeholder underneath
/// the tile layer so the first paint doesn't flash the raw grey grid while
/// tiles stream in.
class _MapView extends StatefulWidget {
  const _MapView({required this.vault, required this.onOpenReceived, required this.onReopen});

  final VaultProvider vault;
  final void Function(ReceivedCapsuleModel) onOpenReceived;
  final void Function(ReceivedCapsuleModel) onReopen;

  @override
  State<_MapView> createState() => _MapViewState();
}

class _MapViewState extends State<_MapView>
    with AutomaticKeepAliveClientMixin {
  bool _tilesLoaded = false;

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final items = widget.vault.receivedCapsules;
    if (items.isEmpty) {
      return Center(
        child: Text(
          'No memories to map yet.',
          style: AppTypography.bodyMd.copyWith(color: AppColors.onSurfaceVariant),
        ),
      );
    }
    final points = [for (final i in items) LatLng(i.latitude, i.longitude)];
    final MapOptions options = points.length == 1
        ? MapOptions(initialCenter: points.first, initialZoom: 12)
        : MapOptions(
            initialCameraFit: CameraFit.bounds(
              bounds: LatLngBounds.fromPoints(points),
              padding: const EdgeInsets.all(56),
              maxZoom: 13,
            ),
          );
    return Stack(
      children: [
        Positioned.fill(
          child: ColoredBox(color: AppColors.surfaceContainer),
        ),
        FlutterMap(
          options: options,
          children: [
            TileLayer(
              urlTemplate: 'https://basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png',
              userAgentPackageName: 'com.timedrop.app',
              retinaMode: RetinaMode.isHighDensity(context),
              // Pre-fetch a wider ring of tiles so panning feels instant and
              // fewer holes appear on first load.
              keepBuffer: 4,
              panBuffer: 2,
              tileBuilder: (context, tileWidget, tile) {
                if (!_tilesLoaded) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted && !_tilesLoaded) {
                      setState(() => _tilesLoaded = true);
                    }
                  });
                }
                return tileWidget;
              },
            ),
            MarkerLayer(
              markers: [
                for (final item in items)
                  Marker(
                    point: LatLng(item.latitude, item.longitude),
                    width: 48,
                    height: 48,
                    child: GestureDetector(
                      onTap: () => item.isViewed
                          ? widget.onReopen(item)
                          : widget.onOpenReceived(item),
                      child: item.isViewed
                          ? _CoverMarker(capsuleId: item.capsuleId)
                          : const _PulsingMarker(),
                    ),
                  ),
              ],
            ),
          ],
        ),
        if (!_tilesLoaded)
          const Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: SkeletonBox(width: 160, height: 160, borderRadius: 24),
              ),
            ),
          ),
      ],
    );
  }
}

class _CoverMarker extends StatelessWidget {
  const _CoverMarker({required this.capsuleId});
  final String capsuleId;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: MediaCacheService.coverPhoto(capsuleId),
      builder: (context, snap) {
        final cover = snap.data;
        return Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.primary, width: 2),
            image: cover != null
                ? DecorationImage(image: MemoryImage(cover), fit: BoxFit.cover)
                : null,
            color: cover == null ? AppColors.primary : null,
          ),
          child: cover == null
              ? const Icon(Icons.play_arrow, color: Colors.white, size: 20)
              : null,
        );
      },
    );
  }
}

class _PulsingMarker extends StatefulWidget {
  const _PulsingMarker();

  @override
  State<_PulsingMarker> createState() => _PulsingMarkerState();
}

class _PulsingMarkerState extends State<_PulsingMarker> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        return Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 16 + t * 28,
              height: 16 + t * 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withValues(alpha: (1 - t) * 0.4),
              ),
            ),
            Container(
              width: 14,
              height: 14,
              decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.primary),
            ),
          ],
        );
      },
    );
  }
}

class _RedeemSheet extends StatefulWidget {
  const _RedeemSheet({required this.onSubmit});
  final Future<void> Function(String) onSubmit;

  @override
  State<_RedeemSheet> createState() => _RedeemSheetState();
}

class _RedeemSheetState extends State<_RedeemSheet> {
  final TextEditingController _controller = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Clipboard prefill runs after the sheet has already opened — instant tap response.
    WidgetsBinding.instance.addPostFrameCallback((_) => _prefillClipboard());
  }

  Future<void> _prefillClipboard() async {
    final clipLink = await ClipboardService.checkClipboardForShareLink();
    if (!mounted || clipLink == null) return;
    _controller.text = clipLink.toUrl();
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _controller.text.length,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      await widget.onSubmit(_controller.text);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        AppSnackbar.showError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // GlassBottomSheet / showModalBottomSheet with isScrollControlled: true
    // does NOT automatically pad for the keyboard — we must add viewInsets.bottom
    // ourselves. SafeArea handles the home indicator at the bottom.
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.containerMargin,
          AppSpacing.md,
          AppSpacing.containerMargin,
          AppSpacing.md + keyboardHeight,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text('Redeem a Drop', style: AppTypography.headlineMd, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _controller,
              textCapitalization: TextCapitalization.characters,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'Paste the link or enter the code'),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: AppSpacing.md),
            PrimaryButton(label: 'Redeem', isLoading: _busy, onPressed: _submit),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
  }
}
