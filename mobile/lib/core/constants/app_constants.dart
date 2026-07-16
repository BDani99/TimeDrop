/// App-wide, non-secret constants. Values here are baked into the share
/// link format and the Radar/proximity UX — changing them changes behavior
/// for every capsule already shared with the old values, so treat them as
/// stable once the app ships.
class AppConstants {
  AppConstants._();

  static const String appName = 'TimeDrop';

  /// Base host for generated share links. MUST match the actual Vercel
  /// deployment domain for `web/` (see terv.md §2).
  static const String shareBaseUrl = 'https://time-drop-pink.vercel.app';

  /// Radar UI outer blur zone radius, in meters.
  static const double radarZoneRadiusMeters = 100;

  /// Distance at which the capsule unlocks (haptic + decrypt + play).
  static const double unlockProximityMeters = 15;

  /// Max video recording duration for CameraScreen.
  static const Duration maxRecordingDuration = Duration(seconds: 60);

  /// Length of the generated share_id (Crockford Base32).
  static const int shareIdLength = 6;
  static const String shareIdAlphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
  static const int shareIdMaxRetries = 5;

  /// Free tier: one capsule before requiring Premium.
  static const int freeDropLimit = 1;

  /// Background-upload safety timeouts. Without these, a stalled video
  /// compression or a hung network request would leave the capsule row stuck
  /// on `pending` ("Uploading…") forever. On timeout the pipeline surfaces a
  /// `failed` status (retryable) instead of hanging silently.
  static const Duration videoCompressTimeout = Duration(seconds: 90);
  static const Duration uploadTimeout = Duration(minutes: 3);

  /// Max automatic attempts for a background upload before it's left as
  /// `failed` for the user to retry manually.
  static const int uploadMaxAttempts = 3;

  /// Content limits for a capsule (Drop Engine phase 1).
  static const int maxCapsulePhotos = 3;
  static const int maxNoteLength = 250;

  /// Fuzzy unlocking (radar phase 3): if the device stays within
  /// [fuzzyUnlockZoneMeters] continuously for [fuzzyUnlockStableDuration],
  /// allow the unlock even if GPS never quite reaches the tight proximity —
  /// avoids frustration from GPS bounce near buildings.
  static const double fuzzyUnlockZoneMeters = 50;
  static const Duration fuzzyUnlockStableDuration = Duration(minutes: 2);

  /// Max metres of a GPS fix's reported accuracy that may count toward the
  /// unlock proximity check. Lets a device standing on the spot (but reading
  /// e.g. "16 m" with ±10 m accuracy) unlock, without letting a very poor fix
  /// unlock from far away.
  static const double maxGpsAccuracyBonusMeters = 20;

  /// Distance under which the radar enters its "closing in" phase.
  static const double radarClosingMeters = 50;

  /// Premium monthly allowances (PaywallScreen copy).
  static const int premiumMonthlyVideoLimit = 3;
  static const int premiumMonthlyPhotoLimit = 10;

  /// Reviewer bypass: tap count on the paywall title before the password
  /// field appears (App Store / Play reviewer QA path).
  static const int reviewerBypassTapCount = 10;

  /// Placeholder subscription pricing shown on the Paywall (mock payments —
  /// real prices come from the store once RevenueCat is configured).
  static const String monthlyPriceLabel = '\$4.99 / month';
  static const String yearlyPriceLabel = '\$39.99 / year';
  static const String yearlySavingLabel = 'Save 33%';

  /// Legal links shown at the bottom of the Paywall. Placeholder pages on the
  /// web domain — replace with real Terms/Privacy pages before launch.
  static const String termsUrl = '$shareBaseUrl/terms';
  static const String privacyUrl = '$shareBaseUrl/privacy';

  /// Human-readable version shown in Settings.
  static const String appVersion = '1.0.0';
}
