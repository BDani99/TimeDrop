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
  static const _keyMirrorDropPhotos = 'pref_mirror_drop_photos';
  static const _keyPendingMerge = 'pending_merge_v1';
  static const _keyOnboardingDone = 'onboarding_completed_v1';

  /// Device-scoped copy of "this person has been through onboarding".
  ///
  /// The server flag alone is account-scoped, and a reinstall means a brand-new
  /// anonymous account — so the same person would be re-onboarded every time.
  /// The device flag alone would re-onboard a returning user on a new phone.
  /// Either one being set is enough.
  static Future<bool> getOnboardingCompleted() async {
    return await _storage.read(key: _keyOnboardingDone) == 'true';
  }

  static Future<void> setOnboardingCompleted(bool value) async {
    await _storage.write(key: _keyOnboardingDone, value: value ? 'true' : 'false');
  }

  /// A merge grant token plus the anonymous account it was issued for, kept
  /// across restarts so a link whose merge failed can still be retried from
  /// Settings until the grant expires. Stored as `<anonUserId>|<token>`.
  static Future<({String anonymousUserId, String token})?> getPendingMerge() async {
    final raw = await _storage.read(key: _keyPendingMerge);
    if (raw == null) return null;
    final separator = raw.indexOf('|');
    if (separator <= 0 || separator == raw.length - 1) return null;
    return (
      anonymousUserId: raw.substring(0, separator),
      token: raw.substring(separator + 1),
    );
  }

  static Future<void> setPendingMerge({
    required String anonymousUserId,
    required String token,
  }) async {
    await _storage.write(key: _keyPendingMerge, value: '$anonymousUserId|$token');
  }

  static Future<void> clearPendingMerge() async {
    await _storage.delete(key: _keyPendingMerge);
  }

  static Future<bool> getUse24HourTime() async {
    final raw = await _storage.read(key: _keyUse24HourTime);
    // Default is 24-hour time; only return false when explicitly set to 'false'.
    return raw != 'false';
  }

  static Future<void> setUse24HourTime(bool value) async {
    await _storage.write(key: _keyUse24HourTime, value: value ? 'true' : 'false');
  }

  /// When true, photos taken with the in-app camera for a drop are mirrored
  /// horizontally after capture (selfie-style). Gallery imports are untouched.
  static Future<bool> getMirrorDropPhotos() async {
    final raw = await _storage.read(key: _keyMirrorDropPhotos);
    return raw == 'true';
  }

  static Future<void> setMirrorDropPhotos(bool value) async {
    await _storage.write(
      key: _keyMirrorDropPhotos,
      value: value ? 'true' : 'false',
    );
  }
}
