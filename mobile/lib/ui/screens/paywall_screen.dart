import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_constants.dart';
import '../../core/env/env.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../providers/payment_provider.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/glass/glass_panel.dart';
import '../widgets/navigation/spring_page_route.dart';
import '../widgets/primary_button.dart';
import 'home_screen.dart';

/// "Premium" upsell screen. Reached either at the end of onboarding
/// ([isOnboarding] = true — offers a "continue with your free capsule" skip
/// and lands on Home) or from the creation free-drop gate ([isOnboarding] =
/// false — offers a subtler "Maybe later" that pops back). Also hosts the
/// hidden reviewer-bypass flow (tap the title N times).
class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key, this.isOnboarding = false});

  final bool isOnboarding;

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  int _titleTapCount = 0;
  bool _showBypassField = false;
  bool _isPurchasing = false;
  bool _isRestoring = false;
  final _bypassController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadOfferings());
  }

  @override
  void dispose() {
    _bypassController.dispose();
    super.dispose();
  }

  Future<void> _loadOfferings() async {
    try {
      await context.read<PaymentProvider>().loadOfferings();
    } catch (e) {
      if (mounted) AppSnackbar.showError(context, e);
    }
  }

  void _onTitleTap() {
    setState(() {
      _titleTapCount++;
      if (_titleTapCount >= AppConstants.reviewerBypassTapCount) {
        _showBypassField = true;
      }
    });
  }

  Future<void> _submitBypass() async {
    if (_bypassController.text == Env.reviewerBypassPassword) {
      await context.read<PaymentProvider>().grantReviewerBypass();
      if (!mounted) return;
      AppSnackbar.showSuccess(context, 'Reviewer access granted.');
      _leaveAfterUnlock();
    } else {
      AppSnackbar.showMessage(context, 'Incorrect code.');
    }
  }

  /// Where to go after the user becomes premium (or restores). In onboarding
  /// we land on a fresh Home; from the creation gate we pop back so they can
  /// finish creating their capsule.
  void _leaveAfterUnlock() {
    if (widget.isOnboarding) {
      Navigator.pushAndRemoveUntil(
        context,
        SpringPageRoute(page: const HomeScreen()),
        (route) => false,
      );
    } else {
      Navigator.pop(context);
    }
  }

  Future<void> _purchase() async {
    setState(() => _isPurchasing = true);
    try {
      final paymentProvider = context.read<PaymentProvider>();
      final packages = paymentProvider.offerings?.current?.availablePackages;
      final package = (packages != null && packages.isNotEmpty) ? packages.first : null;
      final success = await paymentProvider.purchase(package);
      if (!mounted) return;
      if (success) {
        AppSnackbar.showSuccess(context, 'Welcome to Premium!');
        _leaveAfterUnlock();
      }
    } catch (e) {
      if (mounted) AppSnackbar.showError(context, e);
    } finally {
      if (mounted) setState(() => _isPurchasing = false);
    }
  }

  Future<void> _restore() async {
    setState(() => _isRestoring = true);
    try {
      final success = await context.read<PaymentProvider>().restore();
      if (!mounted) return;
      if (success) {
        AppSnackbar.showSuccess(context, 'Purchases restored.');
        _leaveAfterUnlock();
      } else {
        AppSnackbar.showMessage(context, 'No previous purchases found.');
      }
    } catch (e) {
      if (mounted) AppSnackbar.showError(context, e);
    } finally {
      if (mounted) setState(() => _isRestoring = false);
    }
  }

  void _continueFree() {
    // Onboarding already marked itself complete before pushing the paywall,
    // so this just enters the app with the free capsule intact.
    Navigator.pushAndRemoveUntil(
      context,
      SpringPageRoute(page: const HomeScreen()),
      (route) => false,
    );
  }

  Future<void> _openLink(String url) async {
    try {
      final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (!ok && mounted) AppSnackbar.showMessage(context, 'Could not open the link.');
    } catch (e) {
      if (mounted) AppSnackbar.showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final payment = context.watch<PaymentProvider>();

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: ListView(
        children: [
          // ── Hero gradient header ────────────────────────────────────────────
          _PaywallHero(onTitleTap: _onTitleTap),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.containerMargin),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: AppSpacing.md),

                // ── Features ─────────────────────────────────────────────────
                const _FeatureRow(
                  icon: Icons.videocam_outlined,
                  text: 'Video Memories a month',
                  value: '${AppConstants.premiumMonthlyVideoLimit}',
                ),
                const _FeatureRow(
                  icon: Icons.photo_library_outlined,
                  text: 'Unlimited Photo Drops',
                ),
                const _FeatureRow(
                  icon: Icons.lock_outline,
                  text: 'End-to-End Encrypted',
                ),
                const _FeatureRow(
                  icon: Icons.cloud_done_outlined,
                  text: 'Permanent Safekeeping',
                ),
                const SizedBox(height: AppSpacing.lg),

                // ── Plan cards ────────────────────────────────────────────────
                _PlanCard(
                  title: 'Yearly',
                  price: AppConstants.yearlyPriceLabel,
                  badge: AppConstants.yearlySavingLabel,
                  selected: payment.selectedPlan == SubscriptionPlan.yearly,
                  onTap: () => payment.selectPlan(SubscriptionPlan.yearly),
                ),
                const SizedBox(height: AppSpacing.sm),
                _PlanCard(
                  title: 'Monthly',
                  price: AppConstants.monthlyPriceLabel,
                  selected: payment.selectedPlan == SubscriptionPlan.monthly,
                  onTap: () => payment.selectPlan(SubscriptionPlan.monthly),
                ),
                const SizedBox(height: AppSpacing.lg),

                // ── CTA ───────────────────────────────────────────────────────
                PrimaryButton(label: 'Subscribe', isLoading: _isPurchasing, onPressed: _purchase),
                if (widget.isOnboarding) ...[
                  const SizedBox(height: AppSpacing.sm),
                  OutlinedButton(
                    onPressed: _continueFree,
                    child: const Text('Continue with 1 free capsule'),
                  ),
                ] else ...[
                  const SizedBox(height: AppSpacing.sm),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Maybe later'),
                  ),
                ],
                const SizedBox(height: AppSpacing.sm),
                TextButton(
                  onPressed: _isRestoring ? null : _restore,
                  child: Text(_isRestoring ? 'Restoring…' : 'Restore Purchases'),
                ),

                if (_showBypassField) ...[
                  const SizedBox(height: AppSpacing.lg),
                  TextField(
                    controller: _bypassController,
                    obscureText: true,
                    decoration: const InputDecoration(hintText: 'Reviewer password'),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  PrimaryButton(label: 'Unlock', onPressed: _submitBypass),
                ],

                const SizedBox(height: AppSpacing.lg),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton(
                      onPressed: () => _openLink(AppConstants.termsUrl),
                      child: const Text('Terms of Service'),
                    ),
                    Text('·', style: AppTypography.labelSm),
                    TextButton(
                      onPressed: () => _openLink(AppConstants.privacyUrl),
                      child: const Text('Privacy Policy'),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Full-width gradient hero that anchors the paywall emotionally before the
/// user reads any feature bullets or pricing.
class _PaywallHero extends StatelessWidget {
  const _PaywallHero({required this.onTitleTap});

  final VoidCallback onTitleTap;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        AppSpacing.containerMargin,
        top + AppSpacing.lg,
        AppSpacing.containerMargin,
        AppSpacing.xl,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primary,
            AppColors.secondaryContainer,
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Hourglass icon
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.hourglass_bottom, color: Colors.white, size: 32),
          )
              .animate()
              .scale(begin: const Offset(0.7, 0.7), duration: 500.ms, curve: Curves.easeOutBack),
          const SizedBox(height: AppSpacing.md),
          GestureDetector(
            onTap: onTitleTap,
            child: Text(
              'Seal memories\nfor the ones\nyou love.',
              style: AppTypography.headlineLg.copyWith(
                color: Colors.white,
                fontSize: 30,
                height: 1.25,
              ),
            )
                .animate()
                .fadeIn(duration: 500.ms, delay: 120.ms)
                .slideY(begin: 0.1, end: 0, duration: 500.ms, delay: 120.ms),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Your moments, encrypted and waiting for the perfect moment to bloom.',
            style: AppTypography.bodyMd.copyWith(color: Colors.white70),
          )
              .animate()
              .fadeIn(duration: 500.ms, delay: 240.ms),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.title,
    required this.price,
    required this.selected,
    required this.onTap,
    this.badge,
  });

  final String title;
  final String price;
  final bool selected;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.all(AppSpacing.md),
      borderRadius: AppRadii.mdRadius,
      child: InkWell(
        borderRadius: AppRadii.mdRadius,
        onTap: onTap,
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              color: selected ? AppColors.primary : AppColors.outline,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      title,
                      style: AppTypography.headlineMd,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (badge != null) ...[
                    const SizedBox(width: AppSpacing.sm),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(AppRadii.full),
                      ),
                      child: Text(
                        badge!,
                        style: AppTypography.labelSm.copyWith(color: AppColors.onPrimary),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(price, style: AppTypography.bodyMd),
          ],
        ),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.icon, required this.text, this.value});

  final IconData icon;
  final String text;
  final String? value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs + 2),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.primaryContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: AppColors.primary, size: 18),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: value != null
                ? RichText(
                    text: TextSpan(
                      style: AppTypography.bodyMd,
                      children: [
                        TextSpan(
                          text: '$value ',
                          style: AppTypography.bodyMd.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppColors.onSurface,
                          ),
                        ),
                        TextSpan(text: text),
                      ],
                    ),
                  )
                : Text(text, style: AppTypography.bodyMd),
          ),
          const Icon(Icons.check_circle, color: AppColors.primary, size: 18),
        ],
      ),
    );
  }
}
