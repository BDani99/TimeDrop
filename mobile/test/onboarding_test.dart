import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timedrop_mobile/ui/screens/onboarding/onboarding_content.dart';
import 'package:timedrop_mobile/ui/widgets/onboarding/step_progress_line.dart';

void main() {
  group('OnboardingContent', () {
    test('the flow is nine pages: welcome + 4 questions + permissions + '
        'analyzing + 2 features', () {
      expect(OnboardingContent.questions.length, 4);
      expect(OnboardingContent.features.length, 2);
      // 1 + 4 + 1 + 1 + 2
      expect(1 + OnboardingContent.questions.length + 1 + 1 +
          OnboardingContent.features.length, 9);
    });

    test('question keys are unique — a collision would silently overwrite an '
        'answer', () {
      final keys = OnboardingContent.questions.map((q) => q.key).toList();
      expect(keys.toSet().length, keys.length);
    });

    test('every question offers options', () {
      for (final q in OnboardingContent.questions) {
        expect(q.options, isNotEmpty, reason: 'question "${q.key}" has none');
        expect(q.title, isNotEmpty);
      }
    });

    test('every "feeling" option maps to its own paywall headline', () {
      final feeling =
          OnboardingContent.questions.firstWhere((q) => q.key == 'feeling');
      for (final option in feeling.options) {
        final headline = OnboardingContent.headlineFor(option);
        expect(
          headline,
          isNot(OnboardingContent.fallbackHeadline),
          reason: '"$option" falls through to the generic headline',
        );
      }
      // Distinct headlines, so the personalisation is real.
      final headlines =
          feeling.options.map(OnboardingContent.headlineFor).toSet();
      expect(headlines.length, feeling.options.length);
    });

    test('an unknown or skipped feeling falls back instead of throwing', () {
      expect(OnboardingContent.headlineFor(null),
          OnboardingContent.fallbackHeadline);
      expect(OnboardingContent.headlineFor('Something else'),
          OnboardingContent.fallbackHeadline);
    });
  });

  group('StepProgressLine', () {
    Future<void> pump(WidgetTester tester, int step, int total) {
      return tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            child: StepProgressLine(step: step, totalSteps: total),
          ),
        ),
      ));
    }

    testWidgets('renders at the first and last step without overflowing',
        (tester) async {
      await pump(tester, 1, 9);
      expect(tester.takeException(), isNull);

      await pump(tester, 9, 9);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('a step beyond the total clamps instead of overflowing',
        (tester) async {
      await pump(tester, 12, 9);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
