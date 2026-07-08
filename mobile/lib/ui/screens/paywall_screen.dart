import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/env/env.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../providers/payment_provider.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/primary_button.dart';

/// "Premium" upsell screen. Also hosts the hidden reviewer-bypass flow: tap
/// the title `AppConstants.reviewerBypassTapCount` times to reveal a
/// password field that grants local Premium via `Env.reviewerBypassPassword`
/// (for App Store / Play Console QA).
class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key});

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

  void _submitBypass() {
    if (_bypassController.text == Env.reviewerBypassPassword) {
      context.read<PaymentProvider>().grantReviewerBypass();
      AppSnackbar.showSuccess(context, 'Reviewer access granted.');
      Navigator.pop(context);
    } else {
      AppSnackbar.showMessage(context, 'Incorrect code.');
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
        Navigator.pop(context);
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
        Navigator.pop(context);
      } else {
        AppSnackbar.showMessage(context, 'No previous purchases found.');
      }
    } catch (e) {
      if (mounted) AppSnackbar.showError(context, e);
    } finally {
      if (mounted) setState(() => _isRestoring = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
              _FeatureRow(
                text: '${AppConstants.premiumMonthlyVideoLimit} Video Memories a month',
              ),
              const _FeatureRow(text: 'Unlimited Photo Drops'),
              const _FeatureRow(text: 'Permanent Safekeeping'),
              const SizedBox(height: AppSpacing.lg),
              PrimaryButton(label: 'Subscribe', isLoading: _isPurchasing, onPressed: _purchase),
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton(
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
            ],
          ),
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
