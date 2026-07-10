import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../models/capsule_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/capsule_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/vault_provider.dart';
import '../../services/geocoding_service.dart';
import '../../services/supabase_service.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/memory_card.dart';
import '../widgets/primary_button.dart';
import 'camera_screen.dart';
import 'settings_screen.dart';
import 'vault_screen.dart';

/// Home / dashboard: CTA to start a new capsule + a simple list of the
/// user's previously-sent capsules (no "vault"/discovery screen — out of
/// scope for this phase per the spec).
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isLoading = true;
  List<CapsuleModel> _capsules = const [];

  CapsuleProvider? _capsuleProvider;
  int _lastChangeTick = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Re-fetch the sent list whenever a capsule is reserved or a background
    // upload reaches a terminal state, so "Uploading…" flips to the real
    // status without a manual pull-to-refresh.
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

  @override
  void dispose() {
    _capsuleProvider?.removeListener(_onCapsulesChanged);
    super.dispose();
  }

  Future<void> _load() async {
    final userId = context.read<AuthProvider>().userId;
    if (userId == null) return;
    // Load the Vault (best-effort) so the top-bar badge reflects any
    // ready-to-open received capsules. App-scoped provider → cheap re-load.
    unawaited(context.read<VaultProvider>().load(userId));
    setState(() => _isLoading = true);
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
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Lazily reverse-geocodes any sent capsules still missing a city label and
  /// persists them (mirrors VaultProvider._backfillCities), so cards show the
  /// drop location without recomputing on every load.
  Future<void> _backfillCities() async {
    for (var i = 0; i < _capsules.length; i++) {
      final c = _capsules[i];
      if (c.city != null && c.city!.isNotEmpty) continue;
      final city = await GeocodingService.cityFor(c.latitude, c.longitude);
      if (city == null || !mounted) continue;
      try {
        await SupabaseService.updateSentCapsuleCity(capsuleId: c.id, city: city);
      } catch (_) {
        continue; // best-effort; try again next load
      }
      if (!mounted) return;
      final idx = _capsules.indexWhere((x) => x.id == c.id);
      if (idx == -1) continue;
      setState(() => _capsules[idx] = _capsules[idx].copyWithCity(city));
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasUnopenedReady = context.watch<VaultProvider>().ready.isNotEmpty;
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.containerMargin),
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: _VaultIcon(showBadge: hasUnopenedReady),
                    tooltip: 'Vault',
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const VaultScreen()),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.settings_outlined, color: AppColors.onSurfaceVariant),
                    tooltip: 'Settings',
                    onPressed: () => openSettingsScreen(context),
                  ),
                ],
              ),
              Center(
                child: Column(
                  children: [
                    Text('TimeDrop', style: AppTypography.headlineLg),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Begin a new story.',
                      style: AppTypography.bodyMd.copyWith(color: AppColors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Center(
                child: PrimaryButton(
                  label: '+ Leave a Memory',
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const CameraScreen()),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
                  child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
                )
              else if (_capsules.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
                  child: _EmptyState(),
                )
              else
                Column(
                  children: [
                    for (final capsule in _capsules) ...[
                      MemoryCard(
                        city: capsule.city,
                        unlockTime: capsule.unlockTime,
                        status: capsule.status,
                        onRetry: capsule.status == 'failed'
                            ? () => context.read<CapsuleProvider>().retryUpload(capsule.id)
                            : null,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                    ],
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Vault icon with an optional notification dot, shown when a received capsule
/// is ready to physically go open (unlock time reached, key held, unviewed).
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

/// Gamified empty state: a softly pulsing hourglass anchors the eye above the
/// prompt, inviting the first capture.
class _EmptyState extends StatefulWidget {
  const _EmptyState();

  @override
  State<_EmptyState> createState() => _EmptyStateState();
}

class _EmptyStateState extends State<_EmptyState> with SingleTickerProviderStateMixin {
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
