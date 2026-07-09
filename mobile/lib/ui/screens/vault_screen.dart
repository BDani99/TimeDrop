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
import '../widgets/countdown_timer.dart';
import '../widgets/primary_button.dart';
import 'paywall_screen.dart';
import 'radar_screen.dart';
import 'video_player_screen.dart';

enum VaultView { timeline, map }

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  String? get _userId => context.read<AuthProvider>().userId;

  Future<void> _load() async {
    final userId = _userId;
    if (userId == null) return;
    try {
      await context.read<VaultProvider>().load(userId);
    } catch (e) {
      if (mounted) AppSnackbar.showError(context, e);
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
      MaterialPageRoute(
        builder: (_) => RadarScreen(
          shareId: item.shareId,
          encryptionKey: item.encryptionKey!,
          fromName: item.fromName,
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
        MaterialPageRoute(
          builder: (_) => VideoPlayerScreen(
            mediaBytes: content.mediaBytes,
            mimeType: content.mimeType,
            note: content.note,
            photos: content.photos,
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
    // Prefill from the clipboard if it holds a TimeDrop link.
    final clipLink = await ClipboardService.checkClipboardForShareLink();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: AppRadii.lgRadius.topLeft),
      ),
      builder: (_) => _RedeemSheet(
        initialText: clipLink?.toUrl() ?? '',
        onSubmit: _submitCode,
      ),
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
        MaterialPageRoute(
          builder: (_) => RadarScreen(
            shareId: link.shareId,
            encryptionKey: link.encryptionKey,
            fromName: link.fromName,
          ),
        ),
      );
    } else {
      AppSnackbar.showSuccess(context, 'Added to your vault — waiting to unlock.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final vault = context.watch<VaultProvider>();
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('The Vault'),
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
              ],
              selected: {_view},
              onSelectionChanged: (s) => setState(() => _view = s.first),
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        onPressed: _showRedeemSheet,
        child: const Icon(Icons.vpn_key_outlined),
      ),
      body: _view == VaultView.timeline
          ? _TimelineView(
              vault: vault,
              isReopening: _isReopening,
              onRefresh: _load,
              onOpenRadar: _openRadar,
              onReopen: _reopen,
            )
          : _MapView(vault: vault, onOpenRadar: _openRadar, onReopen: _reopen),
    );
  }
}

class _TimelineView extends StatelessWidget {
  const _TimelineView({
    required this.vault,
    required this.isReopening,
    required this.onRefresh,
    required this.onOpenRadar,
    required this.onReopen,
  });

  final VaultProvider vault;
  final bool isReopening;
  final Future<void> Function() onRefresh;
  final void Function(ReceivedCapsuleModel) onOpenRadar;
  final void Function(ReceivedCapsuleModel) onReopen;

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
            const Center(child: CircularProgressIndicator(color: AppColors.primary)),
          if (vault.ready.isNotEmpty) ...[
            _SectionLabel('Ready to open'),
            for (final item in vault.ready) ...[
              _ReadyCard(item: item, onTap: () => onOpenRadar(item)),
              const SizedBox(height: AppSpacing.sm),
            ],
            const SizedBox(height: AppSpacing.md),
          ],
          if (vault.waiting.isNotEmpty) ...[
            _SectionLabel('Waiting'),
            for (final item in vault.waiting) ...[
              _WaitingCard(item: item),
              const SizedBox(height: AppSpacing.sm),
            ],
            const SizedBox(height: AppSpacing.md),
          ],
          if (vault.unlocked.isNotEmpty) ...[
            _SectionLabel('Unlocked'),
            for (final item in vault.unlocked) ...[
              _UnlockedCard(item: item, isBusy: isReopening, onTap: () => onReopen(item)),
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
              MaterialPageRoute(builder: (_) => const PaywallScreen()),
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
  const _ReadyCard({required this.item, required this.onTap});
  final ReceivedCapsuleModel item;
  final VoidCallback onTap;

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

/// Waiting: frosted / locked look, no content, sender + city + countdown,
/// not tappable.
class _WaitingCard extends StatelessWidget {
  const _WaitingCard({required this.item});
  final ReceivedCapsuleModel item;

  @override
  Widget build(BuildContext context) {
    return Container(
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
        ],
      ),
    );
  }
}

/// Unlocked: cached cover thumbnail + date + city + note preview, tap → play.
class _UnlockedCard extends StatelessWidget {
  const _UnlockedCard({required this.item, required this.isBusy, required this.onTap});
  final ReceivedCapsuleModel item;
  final bool isBusy;
  final VoidCallback onTap;

  Future<(Uint8List?, String?)> _load() async {
    final cover = await MediaCacheService.coverPhoto(item.capsuleId);
    final note = await MediaCacheService.noteFor(item.capsuleId);
    return (cover, note);
  }

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
    return InkWell(
      borderRadius: AppRadii.mdRadius,
      onTap: isBusy ? null : onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: AppRadii.mdRadius,
          border: Border.all(color: AppColors.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: FutureBuilder<(Uint8List?, String?)>(
          future: _load(),
          builder: (context, snap) {
            final cover = snap.data?.$1;
            final note = snap.data?.$2;
            return Row(
              children: [
                SizedBox(
                  width: 92,
                  height: 92,
                  child: cover != null
                      ? Image.memory(cover, fit: BoxFit.cover)
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
            );
          },
        ),
      ),
    );
  }
}

class _MapView extends StatelessWidget {
  const _MapView({required this.vault, required this.onOpenRadar, required this.onReopen});

  final VaultProvider vault;
  final void Function(ReceivedCapsuleModel) onOpenRadar;
  final void Function(ReceivedCapsuleModel) onReopen;

  @override
  Widget build(BuildContext context) {
    final items = vault.receivedCapsules;
    if (items.isEmpty) {
      return Center(
        child: Text(
          'No memories to map yet.',
          style: AppTypography.bodyMd.copyWith(color: AppColors.onSurfaceVariant),
        ),
      );
    }
    final center = LatLng(items.first.latitude, items.first.longitude);
    return FlutterMap(
      options: MapOptions(initialCenter: center, initialZoom: 4),
      children: [
        // Dark CartoDB basemap for the "global overview" look.
        TileLayer(
          urlTemplate: 'https://basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
          userAgentPackageName: 'com.timedrop.app',
          retinaMode: RetinaMode.isHighDensity(context),
        ),
        MarkerLayer(
          markers: [
            for (final item in items)
              Marker(
                point: LatLng(item.latitude, item.longitude),
                width: 48,
                height: 48,
                child: GestureDetector(
                  onTap: () => item.isViewed ? onReopen(item) : onOpenRadar(item),
                  child: item.isViewed
                      ? _CoverMarker(capsuleId: item.capsuleId)
                      : const _PulsingMarker(),
                ),
              ),
          ],
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
  const _RedeemSheet({required this.initialText, required this.onSubmit});
  final String initialText;
  final Future<void> Function(String) onSubmit;

  @override
  State<_RedeemSheet> createState() => _RedeemSheetState();
}

class _RedeemSheetState extends State<_RedeemSheet> {
  late final TextEditingController _controller = TextEditingController(text: widget.initialText);
  bool _busy = false;

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
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
            decoration: const InputDecoration(hintText: 'Paste the link or enter the code'),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: AppSpacing.md),
          PrimaryButton(label: 'Redeem', isLoading: _busy, onPressed: _submit),
          const SizedBox(height: AppSpacing.sm),
        ],
      ),
    );
  }
}
