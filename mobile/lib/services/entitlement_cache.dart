import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Remembers whether the user is subscribed, across restarts and offline
/// launches.
///
/// The subtlety this exists for: RevenueCat's backend lags. Right after a
/// purchase, `Purchases.logIn()` and even the `purchasePackage` reply can still
/// report no active entitlement. Trusting those blindly bounces a user who has
/// just paid straight back to the paywall.
///
/// So sources are classified:
///   * **unverified** — `logIn`, the immediate purchase reply. May only flip
///     false → true. A "no entitlement" answer from these is not believed.
///   * **verified** — an explicit refresh, restore, or entitlement check. These
///     may downgrade, because they are the authoritative read.
class EntitlementCache {
  EntitlementCache._();

  static const _storage = FlutterSecureStorage();
  static const _keyActive = 'cached_subscription_active_v1';

  static bool _value = false;
  static bool get value => _value;

  /// Loads the last known state. Call before configuring RevenueCat so a cold,
  /// offline start does not briefly show a paying user as lapsed.
  static Future<bool> hydrate() async {
    try {
      _value = await _storage.read(key: _keyActive) == 'true';
    } catch (e) {
      debugPrint('Could not read the entitlement cache: $e');
      _value = false;
    }
    return _value;
  }

  /// Returns the value actually adopted, which is not always [next] — an
  /// unverified downgrade is refused.
  static Future<bool> persist(bool next, {required bool verified}) async {
    if (!next && !verified && _value) {
      // Refuse the downgrade: an unverified source claiming "not subscribed"
      // is far more likely to be backend lag than a real cancellation.
      return _value;
    }

    _value = next;
    try {
      await _storage.write(key: _keyActive, value: next ? 'true' : 'false');
    } catch (e) {
      debugPrint('Could not write the entitlement cache: $e');
    }
    return _value;
  }

  /// Called on sign-out: the next account must not inherit this one's state.
  static Future<void> clear() async {
    _value = false;
    try {
      await _storage.delete(key: _keyActive);
    } catch (e) {
      debugPrint('Could not clear the entitlement cache: $e');
    }
  }
}
