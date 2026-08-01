import 'package:flutter/foundation.dart';

import '../models/drop_state_model.dart';
import '../services/supabase_service.dart';

/// Holds the user's drop balance for the UI.
///
/// This is a *mirror*, never the authority: `create_pending_capsule` enforces
/// the real limit inside one database transaction. Everything here exists so
/// the app can show a balance and pre-empt an obviously doomed attempt — if it
/// ever disagrees with the server, the server wins.
class DropBalanceProvider extends ChangeNotifier {
  DropState state = const DropState.unknown();
  bool isLoading = false;

  /// True once a real balance has been fetched at least once. Until then the UI
  /// should avoid showing a hard "0 drops" — it just doesn't know yet.
  bool get isLoaded => _loaded;
  bool _loaded = false;

  Future<void> refresh() async {
    isLoading = true;
    notifyListeners();
    try {
      state = await SupabaseService.fetchDropState();
      _loaded = true;
    } catch (e) {
      // A balance we cannot read must not block drop creation: the server still
      // enforces the quota, so failing open here costs nothing.
      debugPrint('Could not refresh drop balance: $e');
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  /// Applies the post-operation balances returned by `create_pending_capsule`
  /// or `discard_capsule`, avoiding a second round trip.
  void applyFromRpc(Map<String, dynamic> row) {
    state = state.mergeBalances(row);
    _loaded = true;
    notifyListeners();
  }

  /// Called when the signed-in user changes (sign-out, link, deletion).
  void clear() {
    state = const DropState.unknown();
    _loaded = false;
    notifyListeners();
  }
}
