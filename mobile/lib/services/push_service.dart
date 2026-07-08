/// No-op FCM stub. No Firebase project is configured yet (mock/fallback
/// decision — see plan), so this keeps the `fcm_token` plumbing in place
/// (interface + `user_settings.fcm_token` column) without pulling in the
/// `firebase_messaging` dependency or requiring `google-services.json` /
/// `GoogleService-Info.plist`. Swap the body of [registerDevice] for a real
/// FCM token fetch + `user_settings` update once a Firebase project exists.
class PushService {
  PushService._();

  static Future<String?> registerDevice() async {
    // Intentionally no-op: no Firebase project configured.
    return null;
  }
}
