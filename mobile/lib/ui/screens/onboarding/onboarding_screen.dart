import 'dart:async';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../../../core/haptics/app_haptics.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radii.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/settings_provider.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/glass/glass_panel.dart';
import '../../widgets/navigation/spring_page_route.dart';
import '../../widgets/onboarding/step_progress_line.dart';
import '../../widgets/primary_button.dart';
import '../paywall_screen.dart';
import 'onboarding_content.dart';

/// First-run flow: welcome → four questions → permission priming → a short
/// "analyzing" beat → two feature cards → the paywall.
///
/// The paywall is a separate route rather than a tenth page, because it is
/// also reached from the drop gate, the vault banner and the post-open sheet —
/// duplicating it here would fork the pack grid and the reviewer trigger.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, this.landOnVault = false});

  /// True when the user arrived here straight after opening a received memory.
  /// Onboarding replaces the whole stack, so the intent has to be carried
  /// forward by hand — through the paywall and on to Home, which then opens
  /// the Vault. See `enterAppAfterRecipient`.
  final bool landOnVault;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  // 1 welcome + 4 questions + 1 permissions + 1 analyzing + 2 features.
  static const _welcomePage = 0;
  static const _analyzingPage = 6;
  static const _pageCount = 9;

  final _pageController = PageController();
  final Map<String, String> _answers = {};

  int _page = 0;
  bool _finishing = false;

  Timer? _analyzingTimer;
  int _analyzingStep = 0;

  @override
  void dispose() {
    _analyzingTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  // ── Navigation ─────────────────────────────────────────────────────────────

  void _goTo(int page) {
    AppHaptics.selection();
    _pageController.animateToPage(
      page,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  void _next() {
    if (_page >= _pageCount - 1) {
      unawaited(_finish());
      return;
    }
    _goTo(_page + 1);
  }

  void _back() {
    if (_page == 0) return;
    _goTo(_page - 1);
  }

  void _onPageChanged(int page) {
    setState(() => _page = page);
    if (page == _analyzingPage) {
      _startAnalyzing();
    } else {
      _analyzingTimer?.cancel();
    }
  }

  // ── Analyzing beat ─────────────────────────────────────────────────────────

  void _startAnalyzing() {
    _analyzingTimer?.cancel();
    setState(() => _analyzingStep = 0);

    _analyzingTimer = Timer.periodic(const Duration(milliseconds: 1200), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_analyzingStep >= OnboardingContent.analyzingSteps.length - 1) {
        timer.cancel();
        // A short beat on "Ready." before moving on, so the last line is
        // actually readable.
        Future<void>.delayed(const Duration(milliseconds: 800), () {
          if (mounted && _page == _analyzingPage) _next();
        });
        setState(() => _analyzingStep++);
        return;
      }
      setState(() => _analyzingStep++);
    });
  }

  // ── Permissions ────────────────────────────────────────────────────────────

  /// Asks for location and notifications. Never gates progress: a refusal is
  /// recoverable in Settings, and blocking here would strand the user on a
  /// screen they cannot leave.
  Future<void> _requestPermissions() async {
    try {
      await Permission.locationWhenInUse.request();
      await Permission.notification.request();
    } catch (e) {
      debugPrint('Onboarding permission request failed: $e');
    }
    if (mounted) _next();
  }

  // ── Completion ─────────────────────────────────────────────────────────────

  Future<void> _finish() async {
    if (_finishing) return;
    setState(() => _finishing = true);

    final userId = context.read<AuthProvider>().userId;
    if (userId == null) {
      // MainRouter guarantees a session before this screen is built, so this is
      // a genuine fault — surface it instead of sleeping and hoping, which is
      // what the reference implementation did.
      setState(() => _finishing = false);
      AppSnackbar.showError(
        context,
        const _OnboardingSessionException(),
      );
      return;
    }

    try {
      await context.read<SettingsProvider>().completeOnboarding(
            userId,
            answers: _answers,
          );
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        SpringPageRoute(
          page: PaywallScreen(
            isOnboarding: true,
            landOnVault: widget.landOnVault,
            headline: OnboardingContent.headlineFor(_answers['feeling']),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      AppSnackbar.showError(context, e);
      setState(() => _finishing = false);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Back inside the flow steps backwards; only page 0 may leave it. Never
      // during the analyzing beat, which would strand its timer.
      canPop: _page == _welcomePage,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _page != _analyzingPage) _back();
      },
      child: Scaffold(
        backgroundColor: AppColors.surface,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.containerMargin,
                  AppSpacing.sm,
                  AppSpacing.containerMargin,
                  0,
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 40,
                      child: (_page > _welcomePage && _page != _analyzingPage)
                          ? IconButton(
                              padding: EdgeInsets.zero,
                              icon: const Icon(Icons.arrow_back,
                                  color: AppColors.onSurfaceVariant),
                              onPressed: _back,
                            )
                          : null,
                    ),
                    Expanded(
                      child: StepProgressLine(
                        step: _page + 1,
                        totalSteps: _pageCount,
                      ),
                    ),
                    const SizedBox(width: 40),
                  ],
                ),
              ),
              Expanded(
                child: PageView(
                  controller: _pageController,
                  // Navigation is programmatic only: a swipe past an
                  // unanswered question would leave holes in the answers.
                  physics: const NeverScrollableScrollPhysics(),
                  onPageChanged: _onPageChanged,
                  children: [
                    _WelcomePage(onBegin: _next),
                    for (final q in OnboardingContent.questions)
                      _QuestionPage(
                        question: q,
                        selected: _answers[q.key],
                        onSelect: (value) {
                          AppHaptics.selection();
                          setState(() => _answers[q.key] = value);
                          // Auto-advance: the tap IS the answer, so a separate
                          // Continue press is pure friction.
                          Future<void>.delayed(
                            const Duration(milliseconds: 220),
                            () {
                              if (mounted) _next();
                            },
                          );
                        },
                      ),
                    _PermissionPage(
                      onAllow: _requestPermissions,
                      onSkip: _next,
                    ),
                    _AnalyzingPage(step: _analyzingStep),
                    for (final f in OnboardingContent.features)
                      _FeaturePage(
                        feature: f,
                        isLast: f == OnboardingContent.features.last,
                        isBusy: _finishing,
                        onContinue: _next,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Wraps every page so short screens still fill the viewport and tall content
/// scrolls instead of overflowing.
class _PageShell extends StatelessWidget {
  const _PageShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.containerMargin),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: constraints.maxHeight - AppSpacing.containerMargin * 2,
            ),
            child: child,
          ),
        );
      },
    );
  }
}

class _WelcomePage extends StatelessWidget {
  const _WelcomePage({required this.onBegin});

  final VoidCallback onBegin;

  @override
  Widget build(BuildContext context) {
    return _PageShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(),
          Text(OnboardingContent.welcomeTitle, style: AppTypography.headlineLg),
          const SizedBox(height: AppSpacing.md),
          Text(
            OnboardingContent.welcomeBody,
            style: AppTypography.bodyMd.copyWith(color: AppColors.onSurfaceVariant),
          ),
          const Spacer(),
          PrimaryButton(label: OnboardingContent.welcomeCta, onPressed: onBegin),
          const SizedBox(height: AppSpacing.sm),
        ],
      ),
    );
  }
}

class _QuestionPage extends StatelessWidget {
  const _QuestionPage({
    required this.question,
    required this.selected,
    required this.onSelect,
  });

  final OnboardingQuestion question;
  final String? selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return _PageShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppSpacing.md),
          Text(question.title, style: AppTypography.headlineLg),
          const SizedBox(height: AppSpacing.xs),
          Text(
            question.subtitle,
            style: AppTypography.labelSm.copyWith(color: AppColors.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.lg),
          for (final option in question.options) ...[
            _OptionTile(
              label: option,
              selected: selected == option,
              onTap: () => onSelect(option),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          const SizedBox(height: AppSpacing.md),
        ],
      ),
    );
  }
}

class _PermissionPage extends StatelessWidget {
  const _PermissionPage({required this.onAllow, required this.onSkip});

  final VoidCallback onAllow;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return _PageShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(),
          const Icon(Icons.explore_outlined, size: 48, color: AppColors.primary),
          const SizedBox(height: AppSpacing.md),
          Text(OnboardingContent.permissionTitle, style: AppTypography.headlineLg),
          const SizedBox(height: AppSpacing.md),
          Text(
            OnboardingContent.permissionBody,
            style: AppTypography.bodyMd.copyWith(color: AppColors.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            OnboardingContent.permissionNote,
            style: AppTypography.labelSm.copyWith(color: AppColors.onSurfaceVariant),
          ),
          const Spacer(),
          PrimaryButton(label: OnboardingContent.permissionAllow, onPressed: onAllow),
          const SizedBox(height: AppSpacing.sm),
          TextButton(
            onPressed: onSkip,
            child: const Text(OnboardingContent.permissionSkip),
          ),
        ],
      ),
    );
  }
}

class _AnalyzingPage extends StatelessWidget {
  const _AnalyzingPage({required this.step});

  final int step;

  @override
  Widget build(BuildContext context) {
    final steps = OnboardingContent.analyzingSteps;
    return _PageShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(),
          for (var i = 0; i < steps.length; i++) ...[
            AnimatedOpacity(
              duration: const Duration(milliseconds: 280),
              opacity: i <= step ? 1 : 0.25,
              child: Row(
                children: [
                  SizedBox(
                    width: 24,
                    child: i < step
                        ? const Icon(Icons.check, size: 18, color: AppColors.primary)
                        : i == step
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.primary,
                                ),
                              )
                            : null,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: Text(steps[i], style: AppTypography.bodyMd)),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          if (step >= steps.length)
            Text(
              OnboardingContent.analyzingDone,
              style: AppTypography.headlineMd.copyWith(color: AppColors.primary),
            ),
          const Spacer(),
        ],
      ),
    );
  }
}

class _FeaturePage extends StatelessWidget {
  const _FeaturePage({
    required this.feature,
    required this.isLast,
    required this.isBusy,
    required this.onContinue,
  });

  final OnboardingFeature feature;
  final bool isLast;
  final bool isBusy;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return _PageShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(),
          Text(feature.emoji, style: const TextStyle(fontSize: 44)),
          const SizedBox(height: AppSpacing.md),
          Text(feature.title, style: AppTypography.headlineLg),
          const SizedBox(height: AppSpacing.md),
          Text(
            feature.body,
            style: AppTypography.bodyMd.copyWith(color: AppColors.onSurfaceVariant),
          ),
          const Spacer(),
          PrimaryButton(
            label: OnboardingContent.featureCta,
            isLoading: isLast && isBusy,
            onPressed: onContinue,
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: EdgeInsets.zero,
      borderRadius: AppRadii.mdRadius,
      child: InkWell(
        borderRadius: AppRadii.mdRadius,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm + AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            borderRadius: AppRadii.mdRadius,
            border: Border.all(
              color: selected ? AppColors.primary : Colors.transparent,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: AppTypography.bodyMd.copyWith(
                    color: selected
                        ? AppColors.onSecondaryContainer
                        : AppColors.onSurface,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
              if (selected)
                const Icon(Icons.check_circle, color: AppColors.primary, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

/// Surfaced only if the router's session guarantee is somehow broken.
class _OnboardingSessionException implements Exception {
  const _OnboardingSessionException();

  @override
  String toString() =>
      'Could not start your session. Close and reopen the app to try again.';
}
