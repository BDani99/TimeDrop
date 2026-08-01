import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../core/constants/revenuecat_constants.dart';
import '../core/errors/app_exception.dart';
import '../services/entitlement_cache.dart';
import '../services/revenuecat_service.dart';
import 'drop_balance_provider.dart';

enum SubscriptionPlan { monthly, yearly }

/// Owns subscription status and the purchase flow.
///
/// It does NOT own the drop balance — that lives on the server and reaches the
/// app through [DropBalanceProvider]. A pack purchase is credited by the
/// RevenueCat webhook, not by this class, which is why [purchasePack] polls
/// rather than incrementing anything locally.
class PaymentProvider extends ChangeNotifier {
  /// False until the first authoritative answer about the subscription. The
  /// paywall renders a skeleton until then, so a subscriber never sees a flash
  /// of "you are not subscribed" on a cold start.
  bool isReady = false;

  bool isSubscribed = false;
  bool isLoadingOfferings = false;
  Offerings? offerings;
  SubscriptionPlan selectedPlan = SubscriptionPlan.yearly;

  bool get isMockMode => RevenueCatService.isMockMode;

  Future<void> initialize() async {
    // Hydrate first: a paying user starting up offline must not be shown as
    // lapsed while the store is unreachable.
    isSubscribed = await EntitlementCache.hydrate();
    notifyListeners();

    try {
      await RevenueCatService.initialize();
    } catch (e) {
      debugPrint('RevenueCat initialize failed: $e');
    }

    if (isMockMode) {
      // Nothing authoritative will ever arrive; unblock the UI.
      isReady = true;
      notifyListeners();
    }
  }

  /// Binds the RevenueCat customer to the Supabase user and settles the
  /// subscription state. Must run after [initialize] and after a session
  /// exists — the webhook cannot credit drops to an account it cannot resolve.
  Future<void> attachUser(String userId) async {
    if (isMockMode) {
      isReady = true;
      notifyListeners();
      return;
    }

    try {
      final result = await RevenueCatService.logIn(userId);
      // Unverified: right after a purchase this reply is routinely stale, so
      // it may only turn access ON, never off.
      isSubscribed = await EntitlementCache.persist(
        RevenueCatService.hasProEntitlement(result?.customerInfo),
        verified: false,
      );
      notifyListeners();

      await RevenueCatService.syncPurchases();

      final info = await RevenueCatService.refreshCustomerInfo();
      isSubscribed = await EntitlementCache.persist(
        RevenueCatService.hasProEntitlement(info),
        verified: true,
      );
    } catch (e) {
      debugPrint('Could not attach the store account: $e');
    } finally {
      isReady = true;
      notifyListeners();
    }
  }

  /// Called on sign-out so the next account does not inherit this one's state.
  Future<void> detachUser() async {
    await RevenueCatService.logOut();
    await EntitlementCache.clear();
    isSubscribed = false;
    offerings = null;
    notifyListeners();
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

  /// The drop packs, smallest first.
  List<Package> get packPackages {
    final packs = offerings?.all[RevenueCatConstants.offeringPacks]?.availablePackages;
    if (packs == null) return const [];
    final sorted = [...packs];
    sorted.sort((a, b) {
      final ca = RevenueCatConstants.dropsForPackage(a.identifier) ?? 0;
      final cb = RevenueCatConstants.dropsForPackage(b.identifier) ?? 0;
      return ca.compareTo(cb);
    });
    return sorted;
  }

  /// The package matching [selectedPlan].
  ///
  /// The previous implementation always took `availablePackages.first`, so the
  /// plan card the user tapped had no bearing on what they were charged.
  Package? get selectedSubscriptionPackage => packageForPlan(selectedPlan);

  /// Public so the paywall can price BOTH cards without having to flip
  /// [selectedPlan] back and forth mid-build to read the other one's price.
  Package? packageForPlan(SubscriptionPlan plan) {
    final packages = offerings?.current?.availablePackages;
    if (packages == null || packages.isEmpty) return null;

    final wanted =
        plan == SubscriptionPlan.yearly ? PackageType.annual : PackageType.monthly;
    for (final p in packages) {
      if (p.packageType == wanted) return p;
    }

    // Fallback for offerings that use custom identifiers instead of the
    // reserved $rc_monthly / $rc_annual ones.
    final needles = plan == SubscriptionPlan.yearly
        ? const ['annual', 'year']
        : const ['month'];
    for (final p in packages) {
      final id = p.identifier.toLowerCase();
      if (needles.any(id.contains)) return p;
    }
    return null;
  }

  /// Buys the selected subscription. Returns false if the user cancelled.
  Future<bool> purchaseSubscription(DropBalanceProvider drops) async {
    final package = selectedSubscriptionPackage;
    if (package == null) {
      throw const PaymentException('That plan is not available right now.');
    }

    try {
      final info = await RevenueCatService.purchasePackage(package);
      isSubscribed = await EntitlementCache.persist(
        RevenueCatService.hasProEntitlement(info),
        verified: true,
      );
      notifyListeners();

      // Store entitlements can lag a moment behind the purchase reply.
      if (!isSubscribed) await _settleEntitlement();

      // The monthly drops arrive via the webhook, so re-read rather than guess.
      await _pollForDrops(drops);
      return true;
    } on PurchaseCancelledException {
      return false;
    }
  }

  /// Buys a one-off drop pack. Returns false if the user cancelled.
  ///
  /// Packs grant no entitlement — they are credited to the ledger by the
  /// webhook — so success here means "the store took the money", and the drops
  /// follow within seconds.
  Future<bool> purchasePack(Package package, DropBalanceProvider drops) async {
    try {
      await RevenueCatService.purchasePackage(package);
      await _pollForDrops(drops);
      return true;
    } on PurchaseCancelledException {
      return false;
    }
  }

  Future<bool> restore(DropBalanceProvider drops) async {
    final info = await RevenueCatService.restorePurchases();
    isSubscribed = await EntitlementCache.persist(
      RevenueCatService.hasProEntitlement(info),
      verified: true,
    );
    notifyListeners();
    await drops.refresh();
    return isSubscribed;
  }

  /// Re-reads the entitlement a few times, because Google Play and StoreKit
  /// both routinely report an entitlement a beat after the purchase returns.
  Future<void> _settleEntitlement() async {
    for (var attempt = 0; attempt < 3; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 800));
      try {
        final info = await RevenueCatService.refreshCustomerInfo();
        final active = RevenueCatService.hasProEntitlement(info);
        if (active) {
          isSubscribed = await EntitlementCache.persist(true, verified: true);
          notifyListeners();
          return;
        }
      } catch (e) {
        debugPrint('Entitlement settle attempt $attempt failed: $e');
      }
    }
  }

  /// Waits briefly for the webhook to credit the ledger.
  ///
  /// If it has not landed in time we stop rather than error: the purchase DID
  /// succeed, and the drops will appear on the next refresh. Telling the user
  /// something failed here would be false.
  Future<void> _pollForDrops(DropBalanceProvider drops) async {
    final before = drops.state.totalRemaining;
    for (var attempt = 0; attempt < 5; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 800));
      await drops.refresh();
      if (drops.state.totalRemaining > before) return;
    }
  }
}
