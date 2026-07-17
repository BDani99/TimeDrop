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

  /// Loads device-local preferences (not stored in Supabase).
  /// Call once at app start; safe to call multiple times.
  Future<void> loadLocalPrefs() async {
    use24HourTime = await LocalPrefsService.getUse24HourTime();
    mirrorDropPhotos = await LocalPrefsService.getMirrorDropPhotos();
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

  bool get freeDropUsed => settings?.freeDropUsed ?? false;
  int get freeDropsUsed => settings?.freeDropsUsed ?? 0;
  bool get onboardingCompleted => settings?.onboardingCompleted ?? false;
  String? get displayName => settings?.displayName;

  Future<void> setDisplayName(String userId, String name) async {
    await SupabaseService.updateUserDisplayName(userId: userId, displayName: name);
    settings = settings?.copyWith(displayName: name);
    notifyListeners();
  }

  Future<void> incrementFreeDropsUsed() async {
    await SupabaseService.incrementFreeDropsUsed();
    settings = settings?.copyWith(
      freeDropUsed: true,
      freeDropsUsed: freeDropsUsed + 1,
    );
    notifyListeners();
  }

  Future<void> completeOnboarding(String userId, {Map<String, dynamic>? answers}) async {
    await SupabaseService.completeOnboarding(userId: userId, answers: answers);
    settings = settings?.copyWith(onboardingCompleted: true, onboardingAnswers: answers);
    notifyListeners();
  }
}
