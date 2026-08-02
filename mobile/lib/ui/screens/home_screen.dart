import 'dart:async';
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../models/capsule_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/capsule_provider.dart';
import '../../providers/drop_balance_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/vault_provider.dart';
import '../../services/geocoding_service.dart';
import '../../services/supabase_service.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/drop_balance_chip.dart';
import '../widgets/glass/glass_panel.dart';
import '../widgets/loading/skeleton_box.dart';
import '../widgets/memory_card.dart';
import '../widgets/navigation/spring_page_route.dart';
import '../widgets/primary_button.dart';
import 'camera_screen.dart';
import 'paywall_screen.dart';
import 'sent_capsule_detail_screen.dart';
import 'settings_screen.dart';
import 'vault_screen.dart';

/// Home: leave-a-memory CTA, inbox summary for received drops, and the
/// sender's own capsules (active + earlier archive).
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.openVaultOnStart = false});

  /// Pushes the Vault immediately after the first frame. Set when the user has
  /// just finished opening a received memory, so they land on it instead of on
  /// a Home screen that gives no sign of what just happened. Home stays
  /// underneath, so Back behaves exactly as it would any other time.
  final bool openVaultOnStart;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isLoading = true;
  List<CapsuleModel> _capsules = const [];
  bool _showEarlier = false;

  CapsuleProvider? _capsuleProvider;
  int _lastChangeTick = 0;

  final _scrollController = ScrollController();
  bool _snapping = false;

  static const _maxActiveVisible = 3;
  static const _headerCollapse =
      _HomeBrandHeaderDelegate.kMax - _HomeBrandHeaderDelegate.kMin;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load();
      _warmHeader();
      if (widget.openVaultOnStart) _openVault();
    });
  }

  /// Tiny no-op scroll so the first real drag doesn't pay first-paint cost.
  Future<void> _warmHeader() async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (!mounted || !_scrollController.hasClients) return;
    _scrollController.jumpTo(0.5);
    _scrollController.jumpTo(0);
  }

  bool _onScrollEnd(ScrollEndNotification notification) {
    if (_snapping || !_scrollController.hasClients) return false;
    // Only snap the collapsing header range — not the whole list.
    if (notification.depth != 0) return false;
    final offset = _scrollController.offset;
    if (offset <= 0 || offset >= _headerCollapse) return false;

    final target = offset < _headerCollapse * 0.42 ? 0.0 : _headerCollapse;
    _snapping = true;
    _scrollController
        .animateTo(
          target,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        )
        .whenComplete(() {
      if (mounted) _snapping = false;
    });
    return false;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _capsuleProvider?.removeListener(_onCapsulesChanged);
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final provider = context.read<CapsuleProvider>();
    if (!identical(provider, _capsuleProvider)) {
      _capsuleProvider?.removeListener(_onCapsulesChanged);
      _capsuleProvider = provider;
      _lastChangeTick = provider.capsulesChangedTick;
      provider.addListener(_onCapsulesChanged);
    }
  }

  void _onCapsulesChanged() {
    final tick = _capsuleProvider?.capsulesChangedTick ?? 0;
    if (tick != _lastChangeTick && mounted) {
      _lastChangeTick = tick;
      _load();
    }
  }

  Future<void> _load({bool silent = false}) async {
    final userId = context.read<AuthProvider>().userId;
    if (userId == null) return;
    // Always silent: Home watches VaultProvider — a loading notify would
    // rebuild this heavy tree under an open Vault (or mid pop animation).
    unawaited(context.read<VaultProvider>().load(userId, silent: true));
    if (!silent) setState(() => _isLoading = true);
    try {
      final capsules = await SupabaseService.fetchSentCapsules(userId);
      if (!mounted) return;
      await context.read<SettingsProvider>().load(userId);
      if (!mounted) return;
      setState(() => _capsules = capsules);
      unawaited(_backfillCities());
    } catch (e) {
      if (!mounted) return;
      AppSnackbar.showError(context, e);
    } finally {
      if (mounted && _isLoading) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _backfillCities() async {
    for (var i = 0; i < _capsules.length; i++) {
      final c = _capsules[i];
      if (c.city != null && c.city!.isNotEmpty) continue;
      final city = await GeocodingService.cityFor(c.latitude, c.longitude);
      if (city == null || !mounted) continue;
      try {
        await SupabaseService.updateSentCapsuleCity(capsuleId: c.id, city: city);
      } catch (_) {
        continue;
      }
      if (!mounted) return;
      final idx = _capsules.indexWhere((x) => x.id == c.id);
      if (idx == -1) continue;
      setState(() => _capsules[idx] = _capsules[idx].copyWithCity(city));
    }
  }

  List<CapsuleModel> get _active => _capsules
      .where((c) =>
          c.status == 'pending' ||
          c.status == 'failed' ||
          c.unlockTime.isAfter(DateTime.now()))
      .toList();

  List<CapsuleModel> get _earlier => _capsules
      .where((c) =>
          c.status != 'pending' &&
          c.status != 'failed' &&
          !c.unlockTime.isAfter(DateTime.now()))
      .toList();

  /// A sent-capsule row. Pending/failed drops aren't openable yet — they offer
  /// retry instead, and a failed one can also be thrown away outright.
  Widget _memoryCard(CapsuleModel capsule) {
    final isInFlight = capsule.status == 'pending' || capsule.status == 'failed';
    return MemoryCard(
      city: capsule.city,
      unlockTime: capsule.unlockTime,
      createdAt: capsule.createdAt,
      status: capsule.status,
      onRetry: isInFlight
          ? () => context.read<CapsuleProvider>().retryUpload(capsule.id)
          : null,
      onDiscard:
          capsule.status == 'failed' ? () => _confirmDiscard(capsule) : null,
      onTap: isInFlight ? null : () => _openDetail(capsule),
    );
  }

  Future<void> _confirmDiscard(CapsuleModel capsule) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard this drop?'),
        content: const Text(
          'This memory never finished uploading. Discarding removes it and its '
          'share link for good — this cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      final balances = await context.read<CapsuleProvider>().discardUpload(capsule.id);
      if (!mounted) return;
      final drops = context.read<DropBalanceProvider>();
      drops.applyFromRpc(balances);
      AppSnackbar.showSuccess(
        context,
        balances['refunded'] == true
            ? 'Drop discarded — your drop is back.'
            : 'Drop discarded.',
      );
    } catch (e) {
      if (mounted) AppSnackbar.showError(context, e);
    }
  }

  Future<void> _openDetail(CapsuleModel capsule) async {
    await Navigator.push(
      context,
      SpringPageRoute(page: SentCapsuleDetailScreen(capsule: capsule)),
    );
    if (mounted) _load();
  }

  Future<void> _openVault() async {
    await Navigator.push(
      context,
      SpringPageRoute(page: const VaultScreen()),
    );
    if (mounted) _load(silent: true);
  }

  @override
  Widget build(BuildContext context) {
    final vault = context.watch<VaultProvider>();
    final readyCount = vault.ready.length;
    final waitingCount = vault.waiting.length;
    final hasInbox = readyCount > 0 || waitingCount > 0;
    final hasUnopenedReady = readyCount > 0;

    final active = _active;
    final earlier = _earlier;
    final visibleActive = active.take(_maxActiveVisible).toList();
    final overflowActive = active.skip(_maxActiveVisible).toList();
    final archived = [...overflowActive, ...earlier];

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: NotificationListener<ScrollEndNotification>(
          onNotification: _onScrollEnd,
          child: RefreshIndicator(
            color: AppColors.primary,
            onRefresh: _load,
            child: CustomScrollView(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(
                parent: ClampingScrollPhysics(),
              ),
              slivers: [
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _HomeBrandHeaderDelegate(
                    showVaultBadge: hasUnopenedReady,
                    onVault: _openVault,
                    onSettings: () => openSettingsScreen(context),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.containerMargin,
                    AppSpacing.md,
                    AppSpacing.containerMargin,
                    AppSpacing.containerMargin,
                  ),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      Center(
                        child: PrimaryButton(
                          label: 'Leave a Memory',
                          onPressed: () => Navigator.push(
                            context,
                            SpringPageRoute(page: const CameraScreen()),
                          ),
                        ),
                      ),
                      if (hasInbox) ...[
                        const SizedBox(height: AppSpacing.md),
                        _InboxStrip(
                          readyCount: readyCount,
                          waitingCount: waitingCount,
                          onTap: _openVault,
                        ),
                      ],
                      const SizedBox(height: AppSpacing.lg),
                      if (_isLoading)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
                          child: Column(
                            children: [
                              SkeletonMemoryCard(),
                              SizedBox(height: AppSpacing.sm),
                              SkeletonMemoryCard(),
                            ],
                          ),
                        )
                      else ...[
                        Text(
                          'Memories you left',
                          textAlign: TextAlign.center,
                          style: AppTypography.headlineMd,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          'Drops you created and shared.',
                          textAlign: TextAlign.center,
                          style: AppTypography.labelSm.copyWith(
                            color: AppColors.onSurfaceVariant,
                          ),
                        ),
                        // The balance belongs to this section, not to the CTA:
                        // it answers "how many of these can I still make?",
                        // which is the question the list itself raises. Shown
                        // even with no memories yet — that is exactly when a
                        // new user wants to know what they have.
                        const SizedBox(height: AppSpacing.sm),
                        Center(
                          child: DropBalanceChip(
                            onTap: () => Navigator.push(
                              context,
                              SpringPageRoute(page: const PaywallScreen()),
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        if (_capsules.isEmpty)
                          const Padding(
                            padding:
                                EdgeInsets.symmetric(vertical: AppSpacing.lg),
                            child: _EmptyState(),
                          ),
                        for (final capsule in visibleActive) ...[
                          _memoryCard(capsule),
                          const SizedBox(height: AppSpacing.sm),
                        ],
                        if (archived.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.sm),
                          Builder(
                            builder: (context) {
                              final expanded =
                                  _showEarlier || visibleActive.isEmpty;
                              return Column(
                                children: [
                                  if (visibleActive.isNotEmpty)
                                    TextButton(
                                      onPressed: () => setState(
                                        () => _showEarlier = !_showEarlier,
                                      ),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            expanded
                                                ? 'Hide earlier drops'
                                                : 'Earlier drops (${archived.length})',
                                            style: AppTypography.labelMd
                                                .copyWith(
                                              color: AppColors.primary,
                                            ),
                                          ),
                                          Icon(
                                            expanded
                                                ? Icons.expand_less
                                                : Icons.expand_more,
                                            color: AppColors.primary,
                                            size: 20,
                                          ),
                                        ],
                                      ),
                                    ),
                                  if (expanded)
                                    for (final capsule in archived) ...[
                                      _memoryCard(capsule),
                                      const SizedBox(height: AppSpacing.sm),
                                    ],
                                ],
                              );
                            },
                          ),
                        ],
                      ],
                    ]),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Collapsing header: icons stay pinned; TimeDrop scales into the bar.
/// Uses Transform.scale (cheap) instead of changing fontSize every frame.
class _HomeBrandHeaderDelegate extends SliverPersistentHeaderDelegate {
  _HomeBrandHeaderDelegate({
    required this.showVaultBadge,
    required this.onVault,
    required this.onSettings,
  });

  final bool showVaultBadge;
  final VoidCallback onVault;
  final VoidCallback onSettings;

  static const double kMin = 56;
  static const double kMax = 118;

  static final _titleStyle = AppTypography.headlineLg.copyWith(
    fontSize: 32,
    height: 1.0,
  );
  static final _subtitleStyle = AppTypography.bodyMd.copyWith(
    color: AppColors.onSurfaceVariant,
    height: 1.2,
  );

  @override
  double get minExtent => kMin;

  @override
  double get maxExtent => kMax;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final range = kMax - kMin;
    final t = Curves.easeOutCubic.transform(
      (shrinkOffset / range).clamp(0.0, 1.0),
    );
    final height = (kMax - shrinkOffset).clamp(kMin, kMax);

    final scale = lerpDouble(1.0, 22 / 32, t)!;
    final titleTop = lerpDouble(46, 12, t)!;
    final subtitleOpacity = (1.0 - t * 1.8).clamp(0.0, 1.0);

    return RepaintBoundary(
      child: SizedBox(
        height: height,
        child: ColoredBox(
          color: AppColors.surface,
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned(
                top: 0,
                left: AppSpacing.sm,
                right: AppSpacing.sm,
                height: kMin,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: _VaultIcon(showBadge: showVaultBadge),
                      tooltip: 'Vault',
                      onPressed: onVault,
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.settings_outlined,
                        color: AppColors.onSurfaceVariant,
                      ),
                      tooltip: 'Settings',
                      onPressed: onSettings,
                    ),
                  ],
                ),
              ),
              Positioned(
                top: titleTop,
                left: 64,
                right: 64,
                child: Transform.scale(
                  scale: scale,
                  alignment: Alignment.topCenter,
                  filterQuality: FilterQuality.low,
                  child: Text(
                    'TimeDrop',
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    softWrap: false,
                    style: _titleStyle,
                  ),
                ),
              ),
              if (subtitleOpacity > 0.01)
                Positioned(
                  top: titleTop + 34 * scale,
                  left: 24,
                  right: 24,
                  child: Opacity(
                    opacity: subtitleOpacity,
                    child: Text(
                      'Begin a new story.',
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      softWrap: false,
                      style: _subtitleStyle,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _HomeBrandHeaderDelegate oldDelegate) =>
      oldDelegate.showVaultBadge != showVaultBadge;
}

class _InboxStrip extends StatelessWidget {
  const _InboxStrip({
    required this.readyCount,
    required this.waitingCount,
    required this.onTap,
  });

  final int readyCount;
  final int waitingCount;
  final VoidCallback onTap;

  String get _label {
    final parts = <String>[];
    if (readyCount > 0) parts.add('$readyCount ready to discover');
    if (waitingCount > 0) parts.add('$waitingCount waiting');
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadii.lgRadius,
        child: GlassPanel(
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.inventory_2_outlined,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'In your Vault',
                      style: AppTypography.labelMd.copyWith(
                        color: AppColors.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      _label,
                      style: AppTypography.labelSm.copyWith(
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _VaultIcon extends StatelessWidget {
  const _VaultIcon({required this.showBadge});

  final bool showBadge;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        const Icon(Icons.inventory_2_outlined, color: AppColors.onSurfaceVariant),
        if (showBadge)
          Positioned(
            top: -2,
            right: -2,
            child: Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.surface, width: 1.5),
              ),
            ),
          ),
      ],
    );
  }
}

class _EmptyState extends StatefulWidget {
  const _EmptyState();

  @override
  State<_EmptyState> createState() => _EmptyStateState();
}

class _EmptyStateState extends State<_EmptyState>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final t = Curves.easeInOut.transform(_controller.value);
            return Opacity(
              opacity: 0.35 + 0.35 * t,
              child: Transform.scale(scale: 0.94 + 0.06 * t, child: child),
            );
          },
          child: const Icon(
            Icons.hourglass_empty,
            size: 72,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Your canvas is empty — Tap to capture a moment in time.',
          textAlign: TextAlign.center,
          style: AppTypography.bodyMd.copyWith(color: AppColors.onSurfaceVariant),
        ),
      ],
    );
  }
}
