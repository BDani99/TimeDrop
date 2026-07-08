import 'dart:io';

import 'package:purchases_flutter/purchases_flutter.dart';

import '../core/env/env.dart';
import '../core/errors/app_exception.dart';

/// Thin RevenueCat wrapper. Falls back to Mock mode (simulated successful
/// purchase) whenever no API key is configured, per the cross-cutting rule
/// in terv.md §6 — this is the ONLY place that decides mock vs. real.
class RevenueCatService {
  RevenueCatService._();

  static bool get isMockMode => !Env.isRevenueCatConfigured;

  static Future<void> initialize() async {
    if (isMockMode) return;
    try {
      final apiKey = Platform.isIOS
          ? Env.revenueCatApiKeyIos
          : Env.revenueCatApiKeyAndroid;
      await Purchases.configure(PurchasesConfiguration(apiKey));
    } catch (e) {
      throw PaymentException('Could not initialize the store.', cause: e);
    }
  }

  static Future<Offerings?> fetchOfferings() async {
    if (isMockMode) return null;
    try {
      return await Purchases.getOfferings();
    } catch (e) {
      throw PaymentException('Could not load subscription options.', cause: e);
    }
  }

  /// Returns true on a successful purchase (real or simulated mock).
  static Future<bool> purchasePackage(Package? package) async {
    if (isMockMode) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      return true;
    }
    if (package == null) {
      throw const PaymentException('No subscription package available.');
    }
    try {
      final result = await Purchases.purchasePackage(package);
      return result.entitlements.active.isNotEmpty;
    } catch (e) {
      throw PaymentException('Purchase failed.', cause: e);
    }
  }

  static Future<bool> restorePurchases() async {
    if (isMockMode) return true;
    try {
      final info = await Purchases.restorePurchases();
      return info.entitlements.active.isNotEmpty;
    } catch (e) {
      throw PaymentException('Could not restore purchases.', cause: e);
    }
  }
}
