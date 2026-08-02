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

  /// Drop counts in the order the paywall lists them.
  ///
  /// Used to render the pack tiles even when the store has told us nothing —
  /// in mock mode, before the products exist in App Store Connect / Play
  /// Console, or when the device is offline. Hiding the whole section in those
  /// cases made a headline feature invisible and impossible to review.
  static const List<int> packDropCountsInOrder = [1, 2, 3, 5, 10];

  /// Placeholder prices, shown ONLY until the store's own localised figures
  /// arrive. The real number always comes from `storeProduct.priceString`;
  /// these exist so the tiles have a shape, not so they are accurate.
  static const Map<int, String> placeholderPackPrices = {
    1: r'$0.99',
    2: r'$1.79',
    3: r'$2.49',
    5: r'$3.99',
    10: r'$6.99',
  };
}
