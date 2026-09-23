import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// [LocalStorage] backed by [FlutterSecureStorage] instead of
/// supabase_flutter's own default ([SharedPreferencesLocalStorage]).
///
/// Left unconfigured, `Supabase.initialize()` persists the whole auth
/// session — including the long-lived refresh token — in plain
/// `SharedPreferences` on Android / `NSUserDefaults` on iOS. Whoever can read
/// that file (a rooted/jailbroken device, malware with storage access, an
/// unencrypted local backup, or a forensic tool against a lost phone) can
/// replay the refresh token and act as the user indefinitely — every other
/// credential-shaped value in this app (see [LocalPrefsService],
/// [EntitlementCache], [UploadQueueService]) already goes through secure
/// storage; this was the one gap.
class SecureSessionStorage extends LocalStorage {
  SecureSessionStorage({required this.persistSessionKey});

  final String persistSessionKey;

  static const _storage = FlutterSecureStorage();

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> hasAccessToken() async {
    return await _storage.read(key: persistSessionKey) != null;
  }

  @override
  Future<String?> accessToken() {
    return _storage.read(key: persistSessionKey);
  }

  @override
  Future<void> removePersistedSession() {
    return _storage.delete(key: persistSessionKey);
  }

  @override
  Future<void> persistSession(String persistSessionString) {
    return _storage.write(key: persistSessionKey, value: persistSessionString);
  }
}
