import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../providers/auth_provider.dart';
import '../../providers/settings_provider.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/primary_button.dart';
import 'paywall_screen.dart';

/// Placeholder onboarding questions — tune copy freely. Single-select each.
const List<_OnboardingQuestion> _questions = [
  _OnboardingQuestion(
    key: 'audience',
    title: 'Who are you making memories for?',
    options: ['A partner', 'My family', 'Close friends', 'My future self'],
  ),
  _OnboardingQuestion(
    key: 'moments',
    title: 'What moments matter most to you?',
    options: ['Everyday little joys', 'Big milestones', 'Travels & places', 'Heartfelt messages'],
  ),
  _OnboardingQuestion(
    key: 'cadence',
    title: 'How often do you imagine leaving a memory?',
    options: ['Now and then', 'Every week', 'For special occasions', 'Not sure yet'],
  ),
];

/// New-user intro flow: a few personalization questions, then the paywall.
/// Shown at first launch for fresh users, or after a recipient closes the
/// map/video of a drop they received (see `enterAppAfterRecipient`).
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pageController = PageController();
  final Map<String, String> _answers = {};
  int _page = 0;
  bool _finishing = false;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _select(String key, String value) {
    setState(() => _answers[key] = value);
  }

  Future<void> _next() async {
    if (_page < _questions.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );
      return;
    }
    await _finish();
  }

  Future<void> _finish() async {
    if (_finishing) return;
    setState(() => _finishing = true);
    try {
      final userId = context.read<AuthProvider>().userId;
      if (userId != null) {
        await context.read<SettingsProvider>().completeOnboarding(userId, answers: _answers);
      }
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const PaywallScreen(isOnboarding: true)),
      );
    } catch (e) {
      if (!mounted) return;
      AppSnackbar.showError(context, e);
      setState(() => _finishing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = _questions[_page];
    final hasAnswer = _answers.containsKey(current.key);

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.containerMargin),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  for (var i = 0; i < _questions.length; i++)
                    Expanded(
                      child: Container(
                        margin: EdgeInsets.only(right: i == _questions.length - 1 ? 0 : AppSpacing.xs),
                        height: 4,
                        decoration: BoxDecoration(
                          color: i <= _page ? AppColors.primary : AppColors.outlineVariant,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _questions.length,
                  onPageChanged: (i) => setState(() => _page = i),
                  itemBuilder: (context, index) {
                    final q = _questions[index];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(q.title, style: AppTypography.headlineLg),
                        const SizedBox(height: AppSpacing.lg),
                        for (final option in q.options) ...[
                          _OptionTile(
                            label: option,
                            selected: _answers[q.key] == option,
                            onTap: () => _select(q.key, option),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                        ],
                      ],
                    );
                  },
                ),
              ),
              PrimaryButton(
                label: _page < _questions.length - 1 ? 'Continue' : 'See your options',
                isLoading: _finishing,
                onPressed: hasAnswer ? _next : null,
              ),
              const SizedBox(height: AppSpacing.sm),
              TextButton(
                onPressed: _finishing ? null : _finish,
                child: const Text('Skip'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: AppRadii.mdRadius,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm + AppSpacing.xs,
        ),
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
            Expanded(
              child: Text(
                label,
                style: AppTypography.bodyMd.copyWith(
                  color: selected ? AppColors.onSecondaryContainer : AppColors.onSurface,
                ),
              ),
            ),
            if (selected) const Icon(Icons.check_circle, color: AppColors.primary, size: 20),
          ],
        ),
      ),
    );
  }
}

class _OnboardingQuestion {
  const _OnboardingQuestion({required this.key, required this.title, required this.options});

  final String key;
  final String title;
  final List<String> options;
}
