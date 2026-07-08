/// Build-time configuration via `--dart-define`. Defaults point at the
/// live TimeDrop Supabase project (project-ref `sezxefvrkrpceafzrgdd`) with
/// its public anon key — safe to ship client-side, RLS is the real
/// boundary, see `supabase/migrations/`.
///
/// Example override:
///   flutter run --dart-define=REVENUECAT_API_KEY=xxxx
class Env {
  Env._();

  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://sezxefvrkrpceafzrgdd.supabase.co',
  );

  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNlenhlZnZya3JwY2VhZnpyZ2RkIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODM1MTUzNzEsImV4cCI6MjA5OTA5MTM3MX0.DDGQeF3V3b4xPdBSr07kgBjyKQySRZy4QSlNo5hZ9Lk',
  );

  /// Empty when unset — PaymentProvider treats this as "no key configured"
  /// and falls back to Mock mode per the cross-cutting rule in terv.md §6.
  static const String revenueCatApiKeyIos = String.fromEnvironment(
    'REVENUECAT_API_KEY_IOS',
    defaultValue: '',
  );

  static const String revenueCatApiKeyAndroid = String.fromEnvironment(
    'REVENUECAT_API_KEY_ANDROID',
    defaultValue: '',
  );

  /// Local, non-QA override: typing this string in the reviewer-bypass
  /// password field grants local Premium. Change via --dart-define for
  /// real App Store / Play Console review submissions.
  static const String reviewerBypassPassword = String.fromEnvironment(
    'REVIEWER_BYPASS_PASSWORD',
    defaultValue: 'timedrop-reviewer',
  );

  static bool get isRevenueCatConfigured =>
      revenueCatApiKeyIos.isNotEmpty || revenueCatApiKeyAndroid.isNotEmpty;
}
