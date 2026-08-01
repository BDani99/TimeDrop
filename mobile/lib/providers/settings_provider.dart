import 'package:flutter/foundation.dart';

import '../models/user_settings_model.dart';
import '../services/local_prefs_service.dart';
import '../services/supabase_service.dart';

/// Wraps the current user's `user_settings` row (free_drop_used, fcm_token)
/// and local-only UI preferences (e.g. time format).
class SettingsProvider extends ChangeNotifier {
  UserSettingsModel? settings;

  /// Local preference: whether to display times in 24-hour format.
  bool use24HourTime = true;

  /// Mirror photos taken with the camera when attaching to a drop.
  bool mirrorDropPhotos = false;

  Future<void> load(String userId) async {
    settings = await SupabaseService.fetchUserSettings(userId);
    notifyListeners();
  }

  /// Device-scoped onboarding flag; see [onboardingCompleted].
  bool _localOnboardingCompleted = false;

  /// Loads device-local preferences (not stored in Supabase).
  /// Call once at app start; safe to call multiple times.
  Future<void> loadLocalPrefs() async {
    use24HourTime = await LocalPrefsService.getUse24HourTime();
    mirrorDropPhotos = await LocalPrefsService.getMirrorDropPhotos();
    _localOnboardingCompleted = await LocalPrefsService.getOnboardingCompleted();
    notifyListeners();
  }

  Future<void> setUse24HourTime(bool value) async {
    use24HourTime = value;
    notifyListeners();
    await LocalPrefsService.setUse24HourTime(value);
  }

  Future<void> setMirrorDropPhotos(bool value) async {
    mirrorDropPhotos = value;
    notifyListeners();
    await LocalPrefsService.setMirrorDropPhotos(value);
  }

  /// True when EITHER store says onboarding is done.
  ///
  /// The account flag survives a new device; the device flag survives a
  /// reinstall (which mints a fresh anonymous account, and so would otherwise
  /// replay onboarding for the same person every single time).
  bool get onboardingCompleted =>
      _localOnboardingCompleted || (settings?.onboardingCompleted ?? false);
  String? get displayName => settings?.displayName;

  Future<void> setDisplayName(String userId, String name) async {
    await SupabaseService.updateUserDisplayName(userId: userId, displayName: name);
    settings = settings?.copyWith(displayName: name);
    notifyListeners();
  }

  /// Written to both stores. The device flag goes first and is not allowed to
  /// fail the call: it is what stops a reinstall replaying the whole flow, and
  /// it must survive the server write being unavailable.
  Future<void> completeOnboarding(String userId, {Map<String, dynamic>? answers}) async {
    _localOnboardingCompleted = true;
    notifyListeners();
    try {
      await LocalPrefsService.setOnboardingCompleted(true);
    } catch (e) {
      debugPrint('Could not persist the local onboarding flag: $e');
    }

    await SupabaseService.completeOnboarding(userId: userId, answers: answers);
    settings = settings?.copyWith(onboardingCompleted: true, onboardingAnswers: answers);
    notifyListeners();
  }
}
