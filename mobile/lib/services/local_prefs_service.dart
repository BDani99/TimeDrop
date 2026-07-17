import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Lightweight key-value store for purely local UI preferences that don't
/// need to be synced to the server (e.g. display format choices).
///
/// Uses [FlutterSecureStorage] so no additional dependency is needed — the
/// values are not secrets, but the storage is already available in the project.
class LocalPrefsService {
  LocalPrefsService._();

  static const _storage = FlutterSecureStorage();

  static const _keyUse24HourTime = 'pref_use_24h_time';

  static Future<bool> getUse24HourTime() async {
    final raw = await _storage.read(key: _keyUse24HourTime);
    // Default is 24-hour time; only return false when explicitly set to 'false'.
    return raw != 'false';
  }

  static Future<void> setUse24HourTime(bool value) async {
    await _storage.write(key: _keyUse24HourTime, value: value ? 'true' : 'false');
  }
}
