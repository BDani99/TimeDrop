import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../models/drop_state_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/drop_balance_provider.dart';
import '../../providers/payment_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/supabase_service.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/glass/glass_panel.dart';
import '../widgets/navigation/spring_page_route.dart';
import '../widgets/primary_button.dart';
import 'paywall_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isBusy = false;

  Future<void> _runGuarded(
    Future<void> Function() action, {
    required String successMessage,
  }) async {
    setState(() => _isBusy = true);
    try {
      await action();
      if (!mounted) return;
      AppSnackbar.showSuccess(context, successMessage);
    } catch (e) {
      if (!mounted) return;
      AppSnackbar.showError(context, e);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  /// App Store guideline 3.1.1 requires a restore path, and reviewers look for
  /// it in Settings rather than only behind the paywall.
  Future<void> _restorePurchases() async {
    setState(() => _isBusy = true);
    try {
      final drops = context.read<DropBalanceProvider>();
      final restored = await context.read<PaymentProvider>().restore(drops);
      if (!mounted) return;
      if (restored) {
        AppSnackbar.showSuccess(context, 'Subscription restored.');
      } else {
        AppSnackbar.showMessage(context, 'No previous purchases found.');
      }
    } catch (e) {
      if (mounted) AppSnackbar.showError(context, e);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  /// Opens the platform's own subscription management page. Apple expects an
  /// auto-renewable subscription to be manageable from inside the app.
  Future<void> _manageSubscription() async {
    final url = Platform.isIOS
        ? 'https://apps.apple.com/account/subscriptions'
        : 'https://play.google.com/store/account/subscriptions';
    try {
      final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        AppSnackbar.showMessage(context, 'Could not open the store.');
      }
    } catch (e) {
      if (mounted) AppSnackbar.showError(context, e);
    }
  }

  Future<void> _confirmSignOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          'This device goes back to a fresh anonymous account. Your linked '
          'account keeps everything — sign back in any time to get it back.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await _runGuarded(
      () => context.read<AuthProvider>().signOut(),
      successMessage: 'Signed out.',
    );
    if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> _confirmDeleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete account?'),
        content: const Text(
          'This permanently erases your account, every memory you have '
          'recorded, and every memory you have kept.\n\n'
          'Drops you already shared will stop working — the people you sent '
          'them to will no longer be able to open them.\n\n'
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete everything'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isBusy = true);
    try {
      await context.read<AuthProvider>().deleteAccount();
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      if (!mounted) return;
      AppSnackbar.showError(context, e);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.containerMargin),
        children: [
          // ── Account ────────────────────────────────────────────────────────
          GlassPanel(useBlur: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  const Icon(Icons.person_outline, color: AppColors.primary),
                  const SizedBox(width: AppSpacing.sm),
                  Text('Account', style: AppTypography.headlineMd),
                ]),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  auth.isLinked
                      ? 'Your account is linked and your memories are safely backed up.'
                      : 'You\'re using an anonymous, device-only account. Link Apple or Google to keep your memories safe across devices.',
                  style: AppTypography.bodyMd.copyWith(color: AppColors.onSurfaceVariant),
                ),
                if (!auth.isLinked) ...[
                  const SizedBox(height: AppSpacing.md),
                  PrimaryButton(
                    label: 'Continue with Apple',
                    isLoading: _isBusy,
                    onPressed: () => _runGuarded(
                      () => context.read<AuthProvider>().linkApple(),
                      successMessage: 'Account linked.',
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  OutlinedButton(
                    onPressed: _isBusy
                        ? null
                        : () => _runGuarded(
                              () => context.read<AuthProvider>().linkGoogle(),
                              successMessage: 'Account linked.',
                            ),
                    child: const Text('Continue with Google'),
                  ),
                ] else ...[
                  const SizedBox(height: AppSpacing.md),
                  OutlinedButton(
                    onPressed: _isBusy ? null : _confirmSignOut,
                    child: const Text('Sign out'),
                  ),
                ],

                // Only shown while a link succeeded but its data move did not.
                if (auth.hasUnfinishedMerge) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'Some memories from this device have not moved to your '
                    'linked account yet.',
                    style: AppTypography.labelSm.copyWith(color: AppColors.error),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  OutlinedButton(
                    onPressed: _isBusy
                        ? null
                        : () => _runGuarded(
                              () => context.read<AuthProvider>().retryPendingMerge(),
                              successMessage: 'Memories moved across.',
                            ),
                    child: const Text('Retry moving memories'),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // ── Drops & subscription ───────────────────────────────────────────
          _SubscriptionPanel(
            isBusy: _isBusy,
            onRestore: _restorePurchases,
            onManage: _manageSubscription,
            onSeePlans: () => Navigator.push(
              context,
              SpringPageRoute(page: const PaywallScreen()),
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // ── Display ───────────────────────────────────────────────────────
          GlassPanel(useBlur: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  const Icon(Icons.tune_outlined, color: AppColors.onSurfaceVariant),
                  const SizedBox(width: AppSpacing.sm),
                  Text('Display', style: AppTypography.headlineMd),
                ]),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('24-hour time', style: AppTypography.bodyMd),
                          Text(
                            context.watch<SettingsProvider>().use24HourTime
                                ? 'Times shown as 14:30'
                                : 'Times shown as 2:30 PM',
                            style: AppTypography.labelSm
                                .copyWith(color: AppColors.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: context.watch<SettingsProvider>().use24HourTime,
                      activeThumbColor: AppColors.primary,
                      activeTrackColor: AppColors.primary.withValues(alpha: 0.4),
                      onChanged: (v) =>
                          context.read<SettingsProvider>().setUse24HourTime(v),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Mirror camera photos', style: AppTypography.bodyMd),
                          Text(
                            context.watch<SettingsProvider>().mirrorDropPhotos
                                ? 'Drop photos are flipped horizontally'
                                : 'Drop photos keep the camera orientation',
                            style: AppTypography.labelSm
                                .copyWith(color: AppColors.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: context.watch<SettingsProvider>().mirrorDropPhotos,
                      activeThumbColor: AppColors.primary,
                      activeTrackColor: AppColors.primary.withValues(alpha: 0.4),
                      onChanged: (v) =>
                          context.read<SettingsProvider>().setMirrorDropPhotos(v),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // ── Feedback ──────────────────────────────────────────────────────
          GlassPanel(useBlur: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  const Icon(Icons.bug_report_outlined, color: AppColors.onSurfaceVariant),
                  const SizedBox(width: AppSpacing.sm),
                  Text('Feedback', style: AppTypography.headlineMd),
                ]),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Found a bug or have a suggestion? Let us know.',
                  style: AppTypography.bodyMd.copyWith(color: AppColors.onSurfaceVariant),
                ),
                const SizedBox(height: AppSpacing.sm),
                _SettingsTile(
                  icon: Icons.bug_report_outlined,
                  label: 'Report a bug',
                  onTap: () => _showFeedbackSheet(context, initialType: 'bug'),
                ),
                _SettingsTile(
                  icon: Icons.lightbulb_outline,
                  label: 'Send feedback',
                  onTap: () => _showFeedbackSheet(context, initialType: 'feedback'),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // ── Legal ──────────────────────────────────────────────────────────
          GlassPanel(useBlur: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  const Icon(Icons.gavel_outlined, color: AppColors.onSurfaceVariant),
                  const SizedBox(width: AppSpacing.sm),
                  Text('Legal', style: AppTypography.headlineMd),
                ]),
                const SizedBox(height: AppSpacing.xs),
                _SettingsTile(
                  icon: Icons.shield_outlined,
                  label: 'Privacy Policy',
                  onTap: () => _openUrl(context, AppConstants.privacyUrl),
                ),
                _SettingsTile(
                  icon: Icons.article_outlined,
                  label: 'Terms of Service',
                  onTap: () => _openUrl(context, AppConstants.termsUrl),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // ── Privacy / danger zone ──────────────────────────────────────────
          // Kept second-to-last, immediately above About: account deletion is
          // irreversible, so it should be something you scroll down to, not
          // something you pass on the way to the display toggles.
          GlassPanel(useBlur: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  const Icon(Icons.warning_amber_outlined, color: AppColors.error),
                  const SizedBox(width: AppSpacing.sm),
                  Text('Privacy', style: AppTypography.headlineMd),
                ]),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Deleting your account erases every memory you have recorded '
                  'or kept, and stops the drops you already shared from ever '
                  'opening. It cannot be undone.',
                  style: AppTypography.bodyMd.copyWith(color: AppColors.onSurfaceVariant),
                ),
                const SizedBox(height: AppSpacing.sm),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    side: const BorderSide(color: AppColors.error),
                  ),
                  onPressed: _isBusy ? null : _confirmDeleteAccount,
                  child: const Text('Delete account'),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // ── About ──────────────────────────────────────────────────────────
          GlassPanel(useBlur: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  const Icon(Icons.info_outline, color: AppColors.onSurfaceVariant),
                  const SizedBox(width: AppSpacing.sm),
                  Text('About', style: AppTypography.headlineMd),
                ]),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('TimeDrop', style: AppTypography.bodyMd),
                    Text(
                      AppConstants.appVersion,
                      style: AppTypography.labelSm.copyWith(color: AppColors.onSurfaceVariant),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _openUrl(BuildContext context, String url) async {
  try {
    final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the link.')),
      );
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the link.')),
      );
    }
  }
}

Future<void> _showFeedbackSheet(BuildContext context, {required String initialType}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _FeedbackSheet(initialType: initialType),
  );
}

/// Drops and subscription, in one place.
///
/// "Restore purchases" and a link to the store's own subscription management
/// page both live here because App Store review expects to find them in
/// Settings, not only behind the paywall.
class _SubscriptionPanel extends StatelessWidget {
  const _SubscriptionPanel({
    required this.isBusy,
    required this.onRestore,
    required this.onManage,
    required this.onSeePlans,
  });

  final bool isBusy;
  final VoidCallback onRestore;
  final VoidCallback onManage;
  final VoidCallback onSeePlans;

  static String _formatDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final local = dt.toLocal();
    return '${months[local.month - 1]} ${local.day}, ${local.year}';
  }

  String _statusLine(DropState state, bool isSubscribed) {
    if (state.isReviewer) return 'Reviewer access — unlimited drops.';
    switch (state.subscriptionStatus) {
      case 'active':
        final until = state.subscriptionExpiresAt;
        return until == null
            ? 'TimeDrop Pro is active.'
            : 'TimeDrop Pro — renews ${_formatDate(until)}.';
      case 'grace':
        return 'There is a problem with your payment. Your drops stay active '
            'for a few more days.';
      case 'expired':
        return 'Your subscription has ended. Drops you bought separately are '
            'still yours.';
      default:
        return isSubscribed
            ? 'TimeDrop Pro is active.'
            : 'No subscription — you can still buy drops one at a time.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final drops = context.watch<DropBalanceProvider>();
    final payment = context.watch<PaymentProvider>();
    final state = drops.state;

    return GlassPanel(
      useBlur: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            const Icon(Icons.confirmation_number_outlined, color: AppColors.primary),
            const SizedBox(width: AppSpacing.sm),
            Text('Drops', style: AppTypography.headlineMd),
          ]),
          const SizedBox(height: AppSpacing.sm),

          Text(
            _statusLine(state, payment.isSubscribed),
            style: AppTypography.bodyMd.copyWith(color: AppColors.onSurfaceVariant),
          ),

          // Only shown once a real balance has arrived — a placeholder zero
          // would read as "you have nothing" while it is still loading.
          if (drops.isLoaded && !state.isReviewer) ...[
            const SizedBox(height: AppSpacing.md),
            _BalanceRow(label: 'Free', value: state.freeRemaining),
            _BalanceRow(
              label: 'From your subscription',
              value: state.subscriptionRemaining,
              note: state.nextCycleResetAt == null
                  ? null
                  : 'resets ${_formatDate(state.nextCycleResetAt!)}',
            ),
            _BalanceRow(label: 'Bought separately', value: state.purchasedRemaining),
            const Divider(height: AppSpacing.md),
            _BalanceRow(label: 'Total', value: state.totalRemaining, emphasise: true),
          ],

          const SizedBox(height: AppSpacing.md),
          PrimaryButton(
            label: payment.isSubscribed ? 'Get more drops' : 'See plans',
            onPressed: onSeePlans,
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton(
            onPressed: isBusy ? null : onRestore,
            child: Text(isBusy ? 'Restoring…' : 'Restore purchases'),
          ),
          if (payment.isSubscribed) ...[
            const SizedBox(height: AppSpacing.xs),
            TextButton(
              onPressed: onManage,
              child: const Text('Manage subscription'),
            ),
          ],
        ],
      ),
    );
  }
}

class _BalanceRow extends StatelessWidget {
  const _BalanceRow({
    required this.label,
    required this.value,
    this.note,
    this.emphasise = false,
  });

  final String label;
  final int value;
  final String? note;
  final bool emphasise;

  @override
  Widget build(BuildContext context) {
    final style = emphasise
        ? AppTypography.labelMd.copyWith(color: AppColors.onSurface)
        : AppTypography.bodyMd.copyWith(color: AppColors.onSurfaceVariant);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: style),
                if (note != null)
                  Text(
                    note!,
                    style: AppTypography.labelSm
                        .copyWith(color: AppColors.onSurfaceVariant),
                  ),
              ],
            ),
          ),
          Text('$value', style: style),
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 20, color: AppColors.onSurfaceVariant),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(label, style: AppTypography.bodyMd),
            ),
            const Icon(Icons.arrow_forward_ios, size: 14, color: AppColors.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

// ── Feedback bottom sheet ──────────────────────────────────────────────────

class _FeedbackSheet extends StatefulWidget {
  const _FeedbackSheet({required this.initialType});
  final String initialType;

  @override
  State<_FeedbackSheet> createState() => _FeedbackSheetState();
}

class _FeedbackSheetState extends State<_FeedbackSheet> {
  late String _type;
  final _controller = TextEditingController();
  bool _sending = false;

  static const _types = [
    ('bug', Icons.bug_report_outlined, 'Bug report'),
    ('feedback', Icons.lightbulb_outline, 'Feedback / idea'),
    ('other', Icons.chat_bubble_outline, 'Other'),
  ];

  @override
  void initState() {
    super.initState();
    _type = widget.initialType;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final message = _controller.text.trim();
    if (message.isEmpty) {
      AppSnackbar.showMessage(context, 'Please write something before sending.');
      return;
    }
    final userId = context.read<AuthProvider>().userId;
    if (userId == null) {
      AppSnackbar.showMessage(context, 'You need to be signed in.');
      return;
    }
    setState(() => _sending = true);
    try {
      await SupabaseService.submitFeedback(
        userId: userId,
        type: _type,
        message: message,
        appVersion: AppConstants.appVersion,
        platform: Platform.isIOS ? 'ios' : 'android',
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      AppSnackbar.showSuccess(context, 'Thanks — we\'ll take a look!');
    } catch (e) {
      if (mounted) AppSnackbar.showError(context, e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.lgRadius,
      ),
      padding: EdgeInsets.fromLTRB(
        AppSpacing.containerMargin,
        AppSpacing.lg,
        AppSpacing.containerMargin,
        AppSpacing.containerMargin + bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Handle
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
          const SizedBox(height: AppSpacing.lg),
          Text('Send us a message', style: AppTypography.headlineLg),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Your message goes straight to our inbox — no email needed.',
            style: AppTypography.bodyMd.copyWith(color: AppColors.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.md),

          // Type selector chips
          Wrap(
            spacing: AppSpacing.sm,
            children: [
              for (final (value, icon, label) in _types)
                ChoiceChip(
                  avatar: Icon(icon, size: 16),
                  label: Text(label),
                  selected: _type == value,
                  onSelected: (_) => setState(() => _type = value),
                  selectedColor: AppColors.primary.withValues(alpha: 0.15),
                  checkmarkColor: AppColors.primary,
                  side: BorderSide(
                    color: _type == value ? AppColors.primary : AppColors.outlineVariant,
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          // Message field
          TextField(
            controller: _controller,
            maxLines: 5,
            maxLength: 2000,
            textCapitalization: TextCapitalization.sentences,
            autofocus: true,
            decoration: InputDecoration(
              hintText: _type == 'bug'
                  ? 'Describe what happened and what you expected…'
                  : _type == 'feedback'
                      ? 'Share your idea or suggestion…'
                      : 'Write your message…',
              filled: true,
              fillColor: AppColors.surfaceContainerLowest,
              border: OutlineInputBorder(borderRadius: AppRadii.mdRadius),
              enabledBorder: OutlineInputBorder(
                borderRadius: AppRadii.mdRadius,
                borderSide: BorderSide(color: AppColors.outlineVariant.withValues(alpha: 0.6)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: AppRadii.mdRadius,
                borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          PrimaryButton(
            label: 'Send',
            isLoading: _sending,
            onPressed: _send,
          ),
        ],
      ),
    );
  }
}

/// Convenience navigator entry point used from HomeScreen.
void openSettingsScreen(BuildContext context) {
  Navigator.of(context).push(SpringPageRoute(page: const SettingsScreen()));
}
