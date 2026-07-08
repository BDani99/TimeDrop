import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../core/errors/app_exception.dart';
import '../services/revenuecat_service.dart';

/// Owns premium status + the RevenueCat purchase flow, including the Mock
/// mode fallback (no API key configured) mandated by terv.md §6, and the
/// reviewer-bypass override for App Store / Play Console QA.
class PaymentProvider extends ChangeNotifier {
  bool isPremium = false;
  bool isLoadingOfferings = false;
  Offerings? offerings;

  bool get isMockMode => RevenueCatService.isMockMode;

  Future<void> initialize() async {
    await RevenueCatService.initialize();
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
    }
    return success;
  }

  Future<bool> restore() async {
    final success = await RevenueCatService.restorePurchases();
    if (success) {
      isPremium = true;
      notifyListeners();
    }
    return success;
  }

  /// Grants local Premium via the reviewer bypass password field. Only
  /// meaningful on-device; does not touch RevenueCat/Supabase.
  void grantReviewerBypass() {
    isPremium = true;
    notifyListeners();
  }

  void requireCanCreateCapsule({required bool freeDropUsed}) {
    if (freeDropUsed && !isPremium) {
      throw const PaymentException('Your free memory has been used — upgrade to send more.');
    }
  }
}
