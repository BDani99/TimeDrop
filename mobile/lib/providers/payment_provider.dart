import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../core/errors/app_exception.dart';
import '../services/device_service.dart';
import '../services/revenuecat_service.dart';
import '../services/supabase_service.dart';

enum SubscriptionPlan { monthly, yearly }

extension SubscriptionPlanId on SubscriptionPlan {
  String get id => switch (this) {
        SubscriptionPlan.monthly => 'monthly',
        SubscriptionPlan.yearly => 'yearly',
      };
}

/// Owns premium status + the (mock) purchase flow. Premium is persisted
/// per-device via `device_subscriptions` so it survives app restarts and —
/// where secure storage persists — reinstalls, which is what powers
/// device-based "Restore purchases". The RevenueCat mock/real boundary lives
/// in [RevenueCatService]; persistence lives here.
class PaymentProvider extends ChangeNotifier {
  bool isPremium = false;
  bool isLoadingOfferings = false;
  Offerings? offerings;
  SubscriptionPlan selectedPlan = SubscriptionPlan.yearly;

  bool get isMockMode => RevenueCatService.isMockMode;

  Future<void> initialize() async {
    await RevenueCatService.initialize();
  }

  /// Loads any persisted (mock) subscription for this device. Called during
  /// the router bootstrap once a session exists. Non-fatal on failure.
  Future<void> loadPersistedPremium() async {
    try {
      final deviceHash = await DeviceService.getOrCreateDeviceHash();
      final sub = await SupabaseService.getDeviceSubscription(deviceHash);
      if (sub != null && sub.isPremium) {
        isPremium = true;
        notifyListeners();
      }
    } catch (_) {
      // Non-fatal — user simply appears non-premium until a successful check.
    }
  }

  void selectPlan(SubscriptionPlan plan) {
    selectedPlan = plan;
    notifyListeners();
  }

  Future<void> loadOfferings() async {
    isLoadingOfferings = true;
    notifyListeners();
    try {
      offerings = await RevenueCatService.fetchOfferings();
    } finally {
      isLoadingOfferings = false;
      notifyListeners();
    }
  }

  Future<bool> purchase(Package? package) async {
    final success = await RevenueCatService.purchasePackage(package);
    if (success) {
      isPremium = true;
      notifyListeners();
      await _persistPremium(selectedPlan.id);
    }
    return success;
  }

  /// Device-based restore: succeeds only if this device has a prior premium
  /// record (mock) — i.e. the user really did subscribe before.
  Future<bool> restore() async {
    try {
      final deviceHash = await DeviceService.getOrCreateDeviceHash();
      final sub = await SupabaseService.getDeviceSubscription(deviceHash);
      final restored = sub?.isPremium ?? false;
      if (restored) {
        isPremium = true;
        notifyListeners();
      }
      return restored;
    } catch (e) {
      throw PaymentException('Could not restore purchases.', cause: e);
    }
  }

  /// Grants local Premium via the reviewer bypass password field, and
  /// persists it so QA reviewers stay premium across restarts.
  Future<void> grantReviewerBypass() async {
    isPremium = true;
    notifyListeners();
    await _persistPremium('reviewer');
  }

  Future<void> _persistPremium(String type) async {
    try {
      final deviceHash = await DeviceService.getOrCreateDeviceHash();
      await SupabaseService.setDeviceSubscription(
        deviceHash: deviceHash,
        isPremium: true,
        subscriptionType: type,
      );
    } catch (_) {
      // Non-fatal — premium still active in-session; just not persisted.
    }
  }

  void requireCanCreateCapsule({required int dropsUsed, required int freeDropLimit}) {
    if (dropsUsed >= freeDropLimit && !isPremium) {
      throw const PaymentException('Your free memories have been used — upgrade to send more.');
    }
  }
}
