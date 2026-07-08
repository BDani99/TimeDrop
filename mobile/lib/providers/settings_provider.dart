import 'package:flutter/foundation.dart';

import '../models/user_settings_model.dart';
import '../services/supabase_service.dart';

/// Wraps the current user's `user_settings` row (free_drop_used, fcm_token).
class SettingsProvider extends ChangeNotifier {
  UserSettingsModel? settings;

  Future<void> load(String userId) async {
    settings = await SupabaseService.fetchUserSettings(userId);
    notifyListeners();
  }

  bool get freeDropUsed => settings?.freeDropUsed ?? false;

  Future<void> markFreeDropUsed(String userId) async {
    await SupabaseService.markFreeDropUsed(userId);
    settings = settings?.copyWith(freeDropUsed: true);
    notifyListeners();
  }
}
