import 'package:flutter/widgets.dart';

/// Reveals a long list a page at a time as the user scrolls toward its end.
///
/// Both the Home screen's sent drops and the Vault timeline used to build
/// every card in one pass. That is fine at three memories and wasteful at
/// eighty — and the cost lands on the first frame, which is exactly where it
/// is felt.
///
/// The data is already in memory (one fetch, whole list), so this is about how
/// much gets *built*, not about paging the network. Anything that changes the
/// underlying list should call [resetPagination], or a refresh would leave the
/// user scrolled past content that no longer exists.
mixin ScrollPaginationMixin<T extends StatefulWidget> on State<T> {
  /// How many extra items each scroll to the end reveals. Five, because that
  /// is the threshold the lists are tuned around: below it, everything shows
  /// at once and the mechanism never engages.
  static const int pageSize = 5;

  /// How close to the bottom counts as "at the end", in logical pixels. Wide
  /// enough that the next page is usually built before the user gets there.
  static const double _triggerDistance = 400;

  int _visibleCount = pageSize;

  /// How many items may be built right now.
  int get visibleCount => _visibleCount;

  /// Caps [total] to the current page. Use for `itemCount` / `take()`.
  int visibleOf(int total) => total < _visibleCount ? total : _visibleCount;

  bool hasMoreThanVisible(int total) => total > _visibleCount;

  void resetPagination() {
    if (_visibleCount == pageSize) return;
    setState(() => _visibleCount = pageSize);
  }

  /// Grows the window far enough to include [index].
  ///
  /// For the case where something off-page has to be shown regardless of
  /// scrolling — the Vault scrolls to a just-opened memory, and a target that
  /// has not been built yet cannot be scrolled to.
  void ensureVisibleIndex(int index) {
    if (index < _visibleCount) return;
    final needed = ((index + 1) / pageSize).ceil() * pageSize;
    if (!mounted) return;
    setState(() => _visibleCount = needed);
  }

  /// Wire into a `NotificationListener<ScrollNotification>`. Returns false so
  /// the notification keeps bubbling to any other listener.
  bool handleScrollForPagination(ScrollNotification notification, int total) {
    if (_visibleCount >= total) return false;
    // Only the primary scrollable — a horizontal photo strip inside the list
    // must not page the list it sits in.
    if (notification.depth != 0) return false;

    final metrics = notification.metrics;
    if (metrics.axis != Axis.vertical) return false;
    if (metrics.extentAfter > _triggerDistance) return false;

    final next = _visibleCount + pageSize;
    setState(() => _visibleCount = next > total ? total : next);
    return false;
  }
}
