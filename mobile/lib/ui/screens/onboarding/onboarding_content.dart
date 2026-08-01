/// Every word of the onboarding flow, in one place.
///
/// The app has no localization layer, so this is plain English held as `const`
/// data rather than widgets — copy changes should not mean touching layout
/// code, and the sequence should be readable at a glance.
library;

class OnboardingQuestion {
  const OnboardingQuestion({
    required this.key,
    required this.title,
    required this.subtitle,
    required this.options,
  });

  /// Stored in `user_settings.onboarding_answers` under this key.
  final String key;
  final String title;
  final String subtitle;
  final List<String> options;
}

class OnboardingFeature {
  const OnboardingFeature({
    required this.emoji,
    required this.title,
    required this.body,
  });

  final String emoji;
  final String title;
  final String body;
}

class OnboardingContent {
  OnboardingContent._();

  // ── Page 1: welcome ────────────────────────────────────────────────────────
  static const welcomeTitle = 'Leave a moment\nsomewhere in time.';
  static const welcomeBody =
      'Record a video, add photos and a note, then choose a place and a moment '
      'in the future. It stays sealed until they are standing there.';
  static const welcomeCta = 'Begin';

  // ── Pages 2-5: questions ───────────────────────────────────────────────────
  static const questions = <OnboardingQuestion>[
    OnboardingQuestion(
      key: 'recipient',
      title: 'Who is your first drop for?',
      subtitle: 'There is no wrong answer — it just helps us set the tone.',
      options: [
        'Someone I love',
        'My family',
        'A close friend',
        'My future self',
        'I am not sure yet',
      ],
    ),
    OnboardingQuestion(
      key: 'occasion',
      title: 'What are you saving it for?',
      subtitle: 'The moment you want them to open it.',
      options: [
        'A birthday or anniversary',
        'A goodbye',
        'A place that means something to us',
        'A milestone ahead',
        'An ordinary day worth keeping',
      ],
    ),
    OnboardingQuestion(
      key: 'horizon',
      title: 'How far should it travel?',
      subtitle: 'You can change this for every drop you make.',
      options: [
        'A few days',
        'A few months',
        'A year',
        'Several years',
        'I will decide in the moment',
      ],
    ),
    OnboardingQuestion(
      key: 'feeling',
      title: 'What should they feel when it opens?',
      subtitle: 'This is the part people remember.',
      options: ['Loved', 'Surprised', 'Nostalgic', 'Proud', 'Understood'],
    ),
  ];

  // ── Page 6: permission priming ─────────────────────────────────────────────
  static const permissionTitle = 'A memory needs\na place and a moment.';
  static const permissionBody =
      'TimeDrop uses your location twice: when you seal a drop, to mark the '
      'spot — and when you go to open one. Notifications tell you the instant '
      'a drop is ready.';
  static const permissionNote =
      'You can change your mind later in Settings.';
  static const permissionAllow = 'Allow access';
  static const permissionSkip = 'Not now';

  // ── Page 7: analyzing ──────────────────────────────────────────────────────
  static const analyzingSteps = <String>[
    'Reading your answers…',
    'Choosing a delivery style…',
    'Preparing your first drop…',
  ];
  static const analyzingDone = 'Ready.';

  // ── Pages 8-9: features ────────────────────────────────────────────────────
  static const features = <OnboardingFeature>[
    OnboardingFeature(
      emoji: '🔒',
      title: 'Sealed until the moment arrives.',
      body: 'Everything is encrypted on your phone before it ever leaves it. '
          'Not even we can open it early.',
    ),
    OnboardingFeature(
      emoji: '📍',
      title: 'It opens where it happened.',
      body: 'Drop a pin. They have to be standing there to unlock it.\n\n'
          'Your first drop is on us — it is already waiting for you.',
    ),
  ];

  static const featureCta = 'Continue';

  /// The `feeling` answer picks the paywall headline, so the offer reads as a
  /// consequence of what they just told us rather than a generic pitch.
  static const feelingHeadlines = <String, String>{
    'Loved': 'Make them feel loved, exactly when it matters.',
    'Surprised': 'Give them something they never saw coming.',
    'Nostalgic': 'Send a moment back to them, years from now.',
    'Proud': 'Be there for the moment they have been working toward.',
    'Understood': 'Say the thing that is hard to say out loud.',
  };

  static const fallbackHeadline = 'Seal memories for the ones you love.';

  static String headlineFor(String? feeling) =>
      feelingHeadlines[feeling] ?? fallbackHeadline;
}
