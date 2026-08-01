/// How many drops the signed-in user can still create, split by where they came
/// from. Mirrors the `get_drop_state()` RPC — the server is the only authority
/// on these numbers; the client just renders them.
class DropState {
  const DropState({
    required this.freeRemaining,
    required this.subscriptionRemaining,
    required this.purchasedRemaining,
    required this.totalRemaining,
    required this.canCreate,
    required this.isReviewer,
    required this.subscriptionStatus,
    this.nextBucket,
    this.maxUnlockTime,
    this.subscriptionExpiresAt,
    this.nextCycleResetAt,
  });

  /// Placeholder used before the first fetch. `canCreate` is deliberately true:
  /// the server enforces the real limit, so an optimistic client never wrongly
  /// blocks a paying user while the balance is still loading.
  const DropState.unknown()
      : freeRemaining = 0,
        subscriptionRemaining = 0,
        purchasedRemaining = 0,
        totalRemaining = 0,
        canCreate = true,
        isReviewer = false,
        subscriptionStatus = 'none',
        nextBucket = null,
        maxUnlockTime = null,
        subscriptionExpiresAt = null,
        nextCycleResetAt = null;

  final int freeRemaining;
  final int subscriptionRemaining;
  final int purchasedRemaining;
  final int totalRemaining;
  final bool canCreate;
  final bool isReviewer;

  /// One of `none`, `active`, `grace`, `expired`.
  final String subscriptionStatus;

  /// Which bucket the next drop would be taken from, or null when empty.
  final String? nextBucket;

  /// Latest unlock time the next drop may target. Only set when the next drop
  /// would come from the free bucket — paid drops can reach any future date.
  final DateTime? maxUnlockTime;

  final DateTime? subscriptionExpiresAt;
  final DateTime? nextCycleResetAt;

  bool get hasActiveSubscription =>
      subscriptionStatus == 'active' || subscriptionStatus == 'grace';

  /// True when the next drop is horizon-capped, i.e. it is the free one.
  bool get isNextDropFree => !isReviewer && nextBucket == 'free';

  static DateTime? _date(Object? value) =>
      value == null ? null : DateTime.parse(value as String).toLocal();

  static int _int(Object? value) => (value as num?)?.toInt() ?? 0;

  factory DropState.fromJson(Map<String, dynamic> json) {
    return DropState(
      freeRemaining: _int(json['free_remaining']),
      subscriptionRemaining: _int(json['subscription_remaining']),
      purchasedRemaining: _int(json['purchased_remaining']),
      totalRemaining: _int(json['total_remaining']),
      canCreate: json['can_create'] as bool? ?? false,
      isReviewer: json['is_reviewer'] as bool? ?? false,
      subscriptionStatus: json['subscription_status'] as String? ?? 'none',
      nextBucket: json['next_bucket'] as String?,
      maxUnlockTime: _date(json['max_unlock_time']),
      subscriptionExpiresAt: _date(json['subscription_expires_at']),
      nextCycleResetAt: _date(json['next_cycle_reset_at']),
    );
  }

  /// `create_pending_capsule` / `discard_capsule` return the post-operation
  /// balances, so the UI can update without a second round trip. Those replies
  /// carry no subscription metadata, hence the merge with the current state.
  DropState mergeBalances(Map<String, dynamic> json) {
    final free = _int(json['free_remaining']);
    final subscription = _int(json['subscription_remaining']);
    final purchased = _int(json['purchased_remaining']);
    final total = _int(json['total_remaining']);

    final nextBucket = isReviewer
        ? 'reviewer'
        : free > 0
            ? 'free'
            : subscription > 0
                ? 'subscription'
                : purchased > 0
                    ? 'purchased'
                    : null;

    return DropState(
      freeRemaining: free,
      subscriptionRemaining: subscription,
      purchasedRemaining: purchased,
      totalRemaining: total,
      canCreate: isReviewer || total > 0,
      isReviewer: isReviewer,
      subscriptionStatus: subscriptionStatus,
      nextBucket: nextBucket,
      // Only a free drop is horizon-capped. Carrying the old value over would
      // keep the date picker locked to two months after the free drop was
      // spent, until the next full refresh — silently denying a paid drop the
      // reach it was bought for.
      maxUnlockTime: nextBucket == 'free' ? maxUnlockTime : null,
      subscriptionExpiresAt: subscriptionExpiresAt,
      nextCycleResetAt: nextCycleResetAt,
    );
  }
}
