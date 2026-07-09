import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

/// Stable, high-entropy per-device identifier used as the key for
/// (mock) subscription state — see `device_subscriptions`. Generated once
/// and kept in platform secure storage (iOS Keychain / Android Keystore),
/// so "Restore purchases" can find a prior subscription without a linked
/// account. Not personally identifying and never leaves the device except
/// as an opaque lookup key.
class DeviceService {
  DeviceService._();

  static const _storage = FlutterSecureStorage();
  static const _deviceHashKey = 'timedrop_device_hash';
  static const _uuid = Uuid();

  static String? _cached;

  static Future<String> getOrCreateDeviceHash() async {
    if (_cached != null) return _cached!;
    try {
      final existing = await _storage.read(key: _deviceHashKey);
      if (existing != null && existing.isNotEmpty) {
        _cached = existing;
        return existing;
      }
      final generated = _uuid.v4();
      await _storage.write(key: _deviceHashKey, value: generated);
      _cached = generated;
      return generated;
    } catch (_) {
      // Secure storage can fail on some devices/emulators — fall back to an
      // in-memory ephemeral hash so the session still works (subscription
      // just won't persist across restarts in that degraded case).
      _cached ??= _uuid.v4();
      return _cached!;
    }
  }
}
