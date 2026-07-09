import 'package:flutter/material.dart';
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
        MaterialPageRoute(builder: (_) => const HomeScreen()),
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
      MaterialPageRoute(builder: (_) => const HomeScreen()),
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
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.containerMargin),
          child: ListView(
            children: [
              GestureDetector(
                onTap: _onTitleTap,
                child: Text(
                  "Unlock the Premium Vault to secure your family's digital heirloom forever.",
                  style: AppTypography.headlineLg,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              _FeatureRow(text: '${AppConstants.premiumMonthlyVideoLimit} Video Memories a month'),
              const _FeatureRow(text: 'Unlimited Photo Drops'),
              const _FeatureRow(text: 'Permanent Safekeeping'),
              const SizedBox(height: AppSpacing.lg),
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
            ],
          ),
        ),
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
    return InkWell(
      borderRadius: AppRadii.mdRadius,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: selected ? AppColors.secondaryContainer : AppColors.surfaceContainerLowest,
          borderRadius: AppRadii.mdRadius,
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
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
                  Text(title, style: AppTypography.headlineMd),
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
            Text(price, style: AppTypography.bodyMd),
          ],
        ),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          const Icon(Icons.check, color: AppColors.primary, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(text, style: AppTypography.bodyMd)),
        ],
      ),
    );
  }
}
