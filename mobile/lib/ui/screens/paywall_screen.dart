import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:purchases_flutter/purchases_flutter.dart' show Package;
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_constants.dart';
import '../../core/constants/revenuecat_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../providers/drop_balance_provider.dart';
import '../../providers/payment_provider.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/glass/glass_panel.dart';
import '../widgets/hidden_reviewer_trigger.dart';
import '../widgets/navigation/spring_page_route.dart';
import '../widgets/primary_button.dart';
import 'home_screen.dart';

/// Subscription + drop-pack screen. Reached at the end of onboarding
/// ([isOnboarding] = true — offers a skip and lands on Home) or from the drop
/// gate, the vault banner and the post-open sheet ([isOnboarding] = false —
/// offers a subtler "Maybe later" that pops back). Also hosts the hidden
/// store-reviewer unlock (ten taps on the hero title).
class PaywallScreen extends StatefulWidget {
  const PaywallScreen({
    super.key,
    this.isOnboarding = false,
    this.landOnVault = false,
    this.headline,
  });

  final bool isOnboarding;

  /// Only meaningful together with [isOnboarding]: the user got here right
  /// after opening a received memory, so the Home screen we install behind us
  /// should open the Vault. See `enterAppAfterRecipient`.
  final bool landOnVault;

  /// Optional headline, chosen from the user's onboarding answers so the offer
  /// reads as a consequence of what they just said rather than a generic pitch.
  final String? headline;

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  bool _isPurchasing = false;
  bool _isRestoring = false;

  /// Identifier of the pack currently being bought, so only that tile spins.
  String? _purchasingPackId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadOfferings());
  }

  Future<void> _loadOfferings() async {
    try {
      await context.read<PaymentProvider>().loadOfferings();
    } catch (e) {
      if (mounted) AppSnackbar.showError(context, e);
    }
  }

  /// Where to go after the user becomes premium (or restores). In onboarding
  /// we land on a fresh Home; from the creation gate we pop back so they can
  /// finish creating their capsule.
  void _leaveAfterUnlock() {
    if (widget.isOnboarding) {
      Navigator.pushAndRemoveUntil(
        context,
        SpringPageRoute(page: HomeScreen(openVaultOnStart: widget.landOnVault)),
        (route) => false,
      );
    } else {
      Navigator.pop(context);
    }
  }

  Future<void> _purchase() async {
    setState(() => _isPurchasing = true);
    try {
      final payment = context.read<PaymentProvider>();
      final drops = context.read<DropBalanceProvider>();
      final bought = await payment.purchaseSubscription(drops);
      if (!mounted || !bought) return;
      AppSnackbar.showSuccess(
        context,
        'You\'re subscribed — 10 drops a month.',
      );
      _leaveAfterUnlock();
    } catch (e) {
      if (mounted) AppSnackbar.showError(context, e);
    } finally {
      if (mounted) setState(() => _isPurchasing = false);
    }
  }

  Future<void> _purchasePack(Package package) async {
    setState(() => _purchasingPackId = package.identifier);
    try {
      final payment = context.read<PaymentProvider>();
      final drops = context.read<DropBalanceProvider>();
      final before = drops.state.totalRemaining;
      final bought = await payment.purchasePack(package, drops);
      if (!mounted || !bought) return;

      // The webhook credits the ledger, so a slow round trip is normal and is
      // NOT a failure — the money has already changed hands.
      AppSnackbar.showSuccess(
        context,
        drops.state.totalRemaining > before
            ? 'Drops added.'
            : 'Purchase complete — your drops will appear in a moment.',
      );
      if (!widget.isOnboarding) Navigator.pop(context);
    } catch (e) {
      if (mounted) AppSnackbar.showError(context, e);
    } finally {
      if (mounted) setState(() => _purchasingPackId = null);
    }
  }

  Future<void> _restore() async {
    setState(() => _isRestoring = true);
    try {
      final drops = context.read<DropBalanceProvider>();
      final success = await context.read<PaymentProvider>().restore(drops);
      if (!mounted) return;
      if (success) {
        AppSnackbar.showSuccess(context, 'Subscription restored.');
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
      SpringPageRoute(page: HomeScreen(openVaultOnStart: widget.landOnVault)),
      (route) => false,
    );
  }

  /// The pack tiles, from the store when it has answered and from the local
  /// catalogue when it has not.
  ///
  /// A tile with no store package behind it is shown but not tappable: there
  /// is genuinely nothing to buy yet, and a button that opens a store error is
  /// worse than one that plainly says "not available".
  List<Widget> _buildPackTiles(PaymentProvider payment) {
    final packages = payment.packPackages;
    if (packages.isNotEmpty) {
      return [
        for (final pack in packages) ...[
          _PackTile(
            count: RevenueCatConstants.dropsForPackage(pack.identifier),
            price: pack.storeProduct.priceString,
            isBusy: _purchasingPackId == pack.identifier,
            onTap: _purchasingPackId == null ? () => _purchasePack(pack) : null,
          ),
          const SizedBox(height: AppSpacing.xs),
        ],
      ];
    }

    return [
      for (final count in RevenueCatConstants.packDropCountsInOrder) ...[
        _PackTile(
          count: count,
          price: RevenueCatConstants.placeholderPackPrices[count] ?? '—',
          isBusy: false,
          onTap: null,
          isUnavailable: true,
        ),
        const SizedBox(height: AppSpacing.xs),
      ],
      const SizedBox(height: AppSpacing.xs),
      Text(
        payment.isLoadingOfferings
            ? 'Loading prices…'
            : 'Drop packs are not available on this device yet.',
        textAlign: TextAlign.center,
        style: AppTypography.labelSm.copyWith(
          color: AppColors.onSurfaceVariant,
        ),
      ),
    ];
  }

  Future<void> _openLink(String url) async {
    try {
      final ok = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!ok && mounted) {
        AppSnackbar.showMessage(context, 'Could not open the link.');
      }
    } catch (e) {
      if (mounted) AppSnackbar.showError(context, e);
    }
  }

  /// The store's own localised price, falling back to a placeholder only while
  /// offerings are still loading or the store is unreachable.
  String _priceFor(SubscriptionPlan plan, PaymentProvider payment) {
    return payment.packageForPlan(plan)?.storeProduct.priceString ??
        (plan == SubscriptionPlan.yearly
            ? AppConstants.yearlyPriceLabel
            : AppConstants.monthlyPriceLabel);
  }

  @override
  Widget build(BuildContext context) {
    final payment = context.watch<PaymentProvider>();
    final drops = context.watch<DropBalanceProvider>();

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: ListView(
        children: [
          // ── Hero gradient header ────────────────────────────────────────────
          _PaywallHero(headline: widget.headline),

          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.containerMargin,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: AppSpacing.md),

                if (drops.isLoaded) ...[
                  _DropBalanceLine(remaining: drops.state.totalRemaining),
                  const SizedBox(height: AppSpacing.md),
                ],

                // ── Features ─────────────────────────────────────────────────
                const _FeatureRow(
                  icon: Icons.all_inclusive,
                  text: 'Drops every month',
                  value: '10',
                ),
                const _FeatureRow(
                  icon: Icons.bookmark_outline,
                  text: 'Keep the memories you receive',
                ),
                const _FeatureRow(
                  icon: Icons.schedule_outlined,
                  text: 'Send as far ahead as you like',
                ),
                const _FeatureRow(
                  icon: Icons.lock_outline,
                  text: 'End-to-end encrypted',
                ),
                const SizedBox(height: AppSpacing.lg),

                // ── Plan cards ────────────────────────────────────────────────
                _PlanCard(
                  title: 'Yearly',
                  price: _priceFor(SubscriptionPlan.yearly, payment),
                  badge: AppConstants.yearlySavingLabel,
                  selected: payment.selectedPlan == SubscriptionPlan.yearly,
                  onTap: () => payment.selectPlan(SubscriptionPlan.yearly),
                ),
                const SizedBox(height: AppSpacing.sm),
                _PlanCard(
                  title: 'Monthly',
                  price: _priceFor(SubscriptionPlan.monthly, payment),
                  selected: payment.selectedPlan == SubscriptionPlan.monthly,
                  onTap: () => payment.selectPlan(SubscriptionPlan.monthly),
                ),
                const SizedBox(height: AppSpacing.lg),

                // ── CTA ───────────────────────────────────────────────────────
                PrimaryButton(
                  label: 'Subscribe',
                  isLoading: _isPurchasing,
                  onPressed: _purchase,
                ),

                // ── One-off drop packs ────────────────────────────────────────
                // Always rendered, exactly like the subscription cards above.
                // The section used to disappear whenever the store returned
                // nothing (mock mode, products not created yet, offline),
                // which made buying individual drops look like it did not
                // exist at all.
                const SizedBox(height: AppSpacing.lg),
                Text('Just need a few?', style: AppTypography.headlineMd),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'One-off drops. They never expire.',
                  style: AppTypography.labelSm.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                ..._buildPackTiles(payment),
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
                  child: Text(
                    _isRestoring ? 'Restoring…' : 'Restore Purchases',
                  ),
                ),

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
/// "You have N drops" line, so the offer is framed against what they hold.
class _DropBalanceLine extends StatelessWidget {
  const _DropBalanceLine({required this.remaining});

  final int remaining;

  @override
  Widget build(BuildContext context) {
    final text = remaining == 0
        ? 'You have no drops left.'
        : 'You have $remaining drop${remaining == 1 ? '' : 's'} left.';
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.secondaryContainer,
        borderRadius: AppRadii.mdRadius,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.confirmation_number_outlined,
            size: 16,
            color: AppColors.onSecondaryContainer,
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            text,
            style: AppTypography.labelSm.copyWith(
              color: AppColors.onSecondaryContainer,
            ),
          ),
        ],
      ),
    );
  }
}

/// A single one-off drop pack.
class _PackTile extends StatelessWidget {
  const _PackTile({
    required this.count,
    required this.price,
    required this.isBusy,
    required this.onTap,
    this.isUnavailable = false,
  });

  final int? count;
  final String price;
  final bool isBusy;
  final VoidCallback? onTap;

  /// Rendered dimmed: the pack exists in the catalogue, but the store has no
  /// product behind it on this device yet.
  final bool isUnavailable;

  @override
  Widget build(BuildContext context) {
    final label = count == null
        ? 'Drops'
        : '$count drop${count == 1 ? '' : 's'}';
    return Opacity(
      opacity: isUnavailable ? 0.55 : 1,
      child: InkWell(
        borderRadius: AppRadii.mdRadius,
        onTap: isBusy ? null : onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLowest,
            borderRadius: AppRadii.mdRadius,
            border: Border.all(color: AppColors.outlineVariant),
          ),
          child: Row(
            children: [
              Expanded(child: Text(label, style: AppTypography.labelMd)),
              if (isBusy)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.primary,
                  ),
                )
              else
                Text(
                  price,
                  style: AppTypography.labelMd.copyWith(
                    color: AppColors.primary,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PaywallHero extends StatelessWidget {
  const _PaywallHero({this.headline});

  final String? headline;

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
          colors: [AppColors.primary, AppColors.secondaryContainer],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // App icon — no frame
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.asset(
              'assets/icon/android_icon.png',
              width: 56,
              height: 56,
              fit: BoxFit.cover,
            ),
          ).animate().scale(
            begin: const Offset(0.7, 0.7),
            duration: 500.ms,
            curve: Curves.easeOutBack,
          ),
          const SizedBox(height: AppSpacing.md),
          // Ten rapid taps here open the store-reviewer passcode sheet. It is
          // the only entry point, and it looks and behaves like plain text to
          // everyone else.
          HiddenReviewerTrigger(
            child:
                Text(
                      headline ?? 'Seal memories\nfor the ones\nyou love.',
                      style: AppTypography.headlineLg.copyWith(
                        color: Colors.white,
                        fontSize: 30,
                        height: 1.25,
                      ),
                    )
                    .animate()
                    .fadeIn(duration: 500.ms, delay: 120.ms)
                    .slideY(
                      begin: 0.1,
                      end: 0,
                      duration: 500.ms,
                      delay: 120.ms,
                    ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Your moments, encrypted and waiting for the perfect moment to bloom.',
            style: AppTypography.bodyMd.copyWith(color: Colors.white70),
          ).animate().fadeIn(duration: 500.ms, delay: 240.ms),
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
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: selected ? AppColors.primary : AppColors.outline,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: AppTypography.headlineMd),
                  if (badge != null) ...[
                    const SizedBox(height: 2),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(AppRadii.full),
                      ),
                      child: Text(
                        badge!,
                        style: AppTypography.labelSm.copyWith(
                          color: AppColors.onPrimary,
                        ),
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
