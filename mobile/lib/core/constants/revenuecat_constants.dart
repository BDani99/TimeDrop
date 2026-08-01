/// RevenueCat identifiers, mirrored from the TimeDrop project dashboard.
/// Not secrets — the API keys live in [Env].
class RevenueCatConstants {
  RevenueCatConstants._();

  /// The one entitlement, granted by the four subscription products.
  ///
  /// Drop packs are deliberately NOT attached to it: they are consumables
  /// tracked in our own ledger, and attaching them would make someone who
  /// bought a single pack read as an active subscriber.
  static const String entitlementPro = 'pro';

  /// Subscriptions (`offerings.current`) and drop packs.
  static const String offeringDefault = 'default';
  static const String offeringPacks = 'packs';

  /// Pack package identifier → how many drops it grants. The server is the
  /// authority (see `drop_products`); this is only for labelling the paywall.
  static const Map<String, int> packDropCounts = {
    r'$rc_custom_pack_1': 1,
    r'$rc_custom_pack_2': 2,
    r'$rc_custom_pack_3': 3,
    r'$rc_custom_pack_5': 5,
    r'$rc_custom_pack_10': 10,
  };

  static int? dropsForPackage(String identifier) => packDropCounts[identifier];
}
