import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:purchases_flutter/purchases_flutter.dart';

import '../core/constants/revenuecat_constants.dart';
import '../core/env/env.dart';
import '../core/errors/app_exception.dart';

/// Thin RevenueCat wrapper, and the only place that decides mock vs. real.
///
/// Note this project is on `purchases_flutter` 8.x, where `purchasePackage`
/// returns a [CustomerInfo] directly (10.x returns a `PurchaseResult`).
class RevenueCatService {
  RevenueCatService._();

  /// Without an API key the store is unreachable, so the app runs in a mode
  /// where nothing can be bought. Deliberately fail-closed rather than
  /// simulating success: a fake purchase would desynchronise the server-side
  /// drop ledger, which is the actual source of truth.
  static bool get isMockMode => !Env.isRevenueCatConfigured;

  static Future<void> initialize() async {
    if (isMockMode) {
      debugPrint('RevenueCat: no API key configured — store features disabled.');
      return;
    }
    try {
      if (kDebugMode) await Purchases.setLogLevel(LogLevel.warn);
      final apiKey =
          Platform.isIOS ? Env.revenueCatApiKeyIos : Env.revenueCatApiKeyAndroid;
      await Purchases.configure(PurchasesConfiguration(apiKey));
    } catch (e) {
      throw PaymentException('Could not initialize the store.', cause: e);
    }
  }

  /// Binds the RevenueCat customer to the Supabase user.
  ///
  /// This is what makes the webhook able to credit drops: without it every
  /// purchase arrives under an `$RCAnonymousID:...` the server cannot map to
  /// an account, and lands as `unmapped_user`.
  static Future<LogInResult?> logIn(String userId) async {
    if (isMockMode) return null;
    try {
      return await Purchases.logIn(userId);
    } catch (e) {
      throw _mapError(e, 'Could not connect your account to the store.');
    }
  }

  static Future<void> logOut() async {
    if (isMockMode) return;
    try {
      await Purchases.logOut();
    } catch (e) {
      // Logging out of the store is never worth blocking a sign-out for.
      debugPrint('RevenueCat logOut failed: $e');
    }
  }

  static Future<Offerings?> fetchOfferings() async {
    if (isMockMode) return null;
    try {
      return await Purchases.getOfferings();
    } catch (e) {
      throw _mapError(e, 'Could not load purchase options.');
    }
  }

  static Future<CustomerInfo> purchasePackage(Package package) async {
    if (isMockMode) {
      throw const PaymentException('Purchases are not available in this build.');
    }
    try {
      return await Purchases.purchasePackage(package);
    } catch (e) {
      throw _mapError(e, 'The purchase could not be completed.');
    }
  }

  static Future<CustomerInfo> restorePurchases() async {
    if (isMockMode) {
      throw const PaymentException('Purchases are not available in this build.');
    }
    try {
      return await Purchases.restorePurchases();
    } catch (e) {
      throw _mapError(e, 'Could not restore your purchases.');
    }
  }

  /// Pushes any store purchases the backend has not seen yet. Cheap, and it
  /// closes the window after a reinstall where the store knows about a
  /// purchase but RevenueCat has not linked it to this account.
  static Future<void> syncPurchases() async {
    if (isMockMode) return;
    try {
      await Purchases.syncPurchases();
    } catch (e) {
      debugPrint('RevenueCat syncPurchases failed: $e');
    }
  }

  /// An authoritative read: bypasses the SDK's cache.
  static Future<CustomerInfo?> refreshCustomerInfo() async {
    if (isMockMode) return null;
    try {
      await Purchases.invalidateCustomerInfoCache();
      return await Purchases.getCustomerInfo();
    } catch (e) {
      throw _mapError(e, 'Could not check your subscription.');
    }
  }

  /// Named entitlement only.
  ///
  /// Deliberately NOT `entitlements.active.isNotEmpty`: drop packs are
  /// consumables, and any such fallback would read a one-off pack purchase as
  /// an active subscription.
  static bool hasProEntitlement(CustomerInfo? info) =>
      info?.entitlements.active.containsKey(RevenueCatConstants.entitlementPro) ??
      false;

  /// Classifies store failures by RevenueCat's own error code rather than by
  /// matching on message text, which breaks the moment a message is reworded
  /// or localised.
  static AppException _mapError(Object error, String fallback) {
    if (error is! PlatformException) {
      return PaymentException(fallback, cause: error);
    }

    final code = PurchasesErrorHelper.getErrorCode(error);
    return switch (code) {
      PurchasesErrorCode.purchaseCancelledError => const PurchaseCancelledException(),
      PurchasesErrorCode.productAlreadyPurchasedError => const PaymentException(
          'You already own this. Try "Restore purchases".',
        ),
      PurchasesErrorCode.paymentPendingError => const PaymentException(
          'Your payment is still being processed. Your drops will appear once '
          'it completes.',
        ),
      PurchasesErrorCode.networkError => const PaymentException(
          'The store could not be reached. Check your connection and try again.',
        ),
      PurchasesErrorCode.purchaseNotAllowedError => const PaymentException(
          'Purchases are not allowed on this device.',
        ),
      PurchasesErrorCode.storeProblemError => const PaymentException(
          'The store is having trouble right now. Please try again later.',
        ),
      PurchasesErrorCode.productNotAvailableForPurchaseError => const PaymentException(
          'That option is not available yet.',
        ),
      _ => PaymentException(fallback, cause: error),
    };
  }
}
