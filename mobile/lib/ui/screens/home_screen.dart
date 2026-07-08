import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../models/capsule_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/supabase_service.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/memory_card.dart';
import '../widgets/primary_button.dart';
import 'camera_screen.dart';
import 'settings_screen.dart';

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final userId = context.read<AuthProvider>().userId;
    if (userId == null) return;
    setState(() => _isLoading = true);
    try {
      final capsules = await SupabaseService.fetchSentCapsules(userId);
      if (!mounted) return;
      await context.read<SettingsProvider>().load(userId);
      if (!mounted) return;
      setState(() => _capsules = capsules);
    } catch (e) {
      if (!mounted) return;
      AppSnackbar.showError(context, e);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.containerMargin),
            children: [
              Align(
                alignment: Alignment.topRight,
                child: IconButton(
                  icon: const Icon(Icons.settings_outlined, color: AppColors.onSurfaceVariant),
                  onPressed: () => openSettingsScreen(context),
                ),
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
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                  child: Center(
                    child: Text(
                      'Your canvas is empty — Tap to capture a moment in time.',
                      textAlign: TextAlign.center,
                      style: AppTypography.bodyMd.copyWith(color: AppColors.onSurfaceVariant),
                    ),
                  ),
                )
              else
                Column(
                  children: [
                    for (final capsule in _capsules) ...[
                      MemoryCard(shareCode: capsule.shareId, unlockTime: capsule.unlockTime),
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
