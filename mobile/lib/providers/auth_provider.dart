import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;

import '../core/constants/app_constants.dart';
import '../core/errors/app_exception.dart';
import '../services/local_prefs_service.dart';
import '../services/media_cache_service.dart';
import '../services/supabase_service.dart';

enum AuthStatus { unknown, anonymous, linked }

/// Anonymous-first sign-in plus Apple/Google account linking.
///
/// The app is never without a session: signing out or deleting the account
/// immediately mints a fresh anonymous one, because every screen assumes
/// `userId != null` and a sessionless state is an unrecoverable dead end.
class AuthProvider extends ChangeNotifier {
  AuthStatus status = AuthStatus.unknown;
  supa.User? user;

  StreamSubscription<supa.AuthState>? _authSub;
  final StreamController<String?> _userIdController =
      StreamController<String?>.broadcast();

  /// Emits only when the signed-in user actually changes — not on every token
  /// refresh. Listeners re-load per-user state (settings, balances) from here.
  Stream<String?> get userIdChanges => _userIdController.stream;

  /// Set when a link succeeded but moving the anonymous account's data did
  /// not. Settings surfaces a retry while this is true.
  bool hasUnfinishedMerge = false;

  /// Store-reviewer access, granted by passcode. Also honoured server-side, so
  /// a reviewer can genuinely create drops rather than just see the UI.
  bool isReviewer = false;

  String? get userId => user?.id;
  bool get isLinked => status == AuthStatus.linked;

  Future<void> bootstrap() async {
    // Subscribe BEFORE any sign-in so the first `signedIn` event is not missed.
    _authSub ??= SupabaseService.client.auth.onAuthStateChange.listen(
      _onAuthStateChange,
      onError: (Object e) => debugPrint('onAuthStateChange error: $e'),
    );

    final existing = SupabaseService.currentUser;
    if (existing != null) {
      _adopt(existing);
    } else {
      // Every screen assumes a session exists before it renders (see class
      // doc), so a stalled connection here — the normal operating
      // environment for an app whose core loop is "walk to a GPS location" —
      // must not hang the splash screen forever with no way out. Bounding it
      // turns that into a catchable failure the caller can retry.
      _adopt(await SupabaseService.signInAnonymously().timeout(AppConstants.dbCallTimeout));
    }

    hasUnfinishedMerge = await LocalPrefsService.getPendingMerge() != null;
    notifyListeners();
  }

  void _onAuthStateChange(supa.AuthState state) {
    final next = state.session?.user;

    if (next == null) {
      // A signOut we did not initiate (token revoked server-side, session
      // expired). Drop the user so the UI stops rendering stale data; the
      // caller-driven paths always mint a new anonymous session themselves.
      if (user == null) return;
      user = null;
      status = AuthStatus.unknown;
      _userIdController.add(null);
      notifyListeners();
      return;
    }

    final changedIdentity = next.id != user?.id;
    _adopt(next);
    // `tokenRefreshed` fires on a timer with the same user. Notifying on it
    // would rebuild the whole tree every hour for no reason.
    if (changedIdentity) _userIdController.add(next.id);
    notifyListeners();
  }

  void _adopt(supa.User next) {
    user = next;
    status = next.isAnonymous ? AuthStatus.anonymous : AuthStatus.linked;
  }

  // ── Linking ────────────────────────────────────────────────────────────────

  Future<void> linkGoogle() => _link(_googleCredential);
  Future<void> linkApple() => _link(_appleCredential);

  Future<_OAuthCredential> _googleCredential() async {
    final googleUser = await GoogleSignIn().signIn();
    if (googleUser == null) {
      throw const AuthException('Google sign-in was cancelled.');
    }
    final auth = await googleUser.authentication;
    final idToken = auth.idToken;
    if (idToken == null) {
      throw const AuthException('Google sign-in did not return a token.');
    }
    return _OAuthCredential(
      provider: supa.OAuthProvider.google,
      idToken: idToken,
      accessToken: auth.accessToken,
      label: 'Google',
    );
  }

  Future<_OAuthCredential> _appleCredential() async {
    final credential = await SignInWithApple.getAppleIDCredential(
      scopes: [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
    );
    final idToken = credential.identityToken;
    if (idToken == null) {
      throw const AuthException('Apple sign-in did not return a token.');
    }
    return _OAuthCredential(
      provider: supa.OAuthProvider.apple,
      idToken: idToken,
      accessToken: null,
      label: 'Apple',
    );
  }

  /// Links an OAuth identity to the current account.
  ///
  /// `signInWithIdToken` merges into the current anonymous session when the
  /// identity is new. When it already belongs to a pre-existing user, Supabase
  /// signs us into THAT user instead — stranding this device's rows under the
  /// old anonymous id. The merge grant, taken before the OAuth round trip, is
  /// what lets the server prove we owned that anonymous account.
  Future<void> _link(Future<_OAuthCredential> Function() getCredential) async {
    final previousId = user?.id;
    final wasAnonymous = status == AuthStatus.anonymous;

    // Must be obtained while we are still the anonymous user.
    String? grantToken;
    if (wasAnonymous && previousId != null) {
      try {
        grantToken = await SupabaseService.requestMergeGrant().timeout(AppConstants.dbCallTimeout);
      } catch (e) {
        debugPrint('Could not pre-authorize the account merge: $e');
      }
    }

    final _OAuthCredential credential;
    try {
      credential = await getCredential();
    } on AuthException {
      rethrow;
    } catch (e) {
      throw AuthException('Sign-in was cancelled or failed.', cause: e);
    }

    try {
      final response = await SupabaseService.client.auth
          .signInWithIdToken(
            provider: credential.provider,
            idToken: credential.idToken,
            accessToken: credential.accessToken,
          )
          .timeout(AppConstants.dbCallTimeout);
      final linked = response.user;
      if (linked == null) {
        throw const AuthException('Sign-in did not return an account.');
      }
      _adopt(linked);
      notifyListeners();
    } catch (e) {
      if (e is AuthException) rethrow;
      throw AuthException(
        'Could not link your ${credential.label} account. '
        'It may not be configured yet.',
        cause: e,
      );
    }

    final newId = user?.id;
    if (previousId == null || newId == null || previousId == newId) return;

    if (grantToken == null) {
      // We are signed in, but cannot prove we owned the old account, so the
      // server will refuse the merge. Say so instead of pretending it worked.
      hasUnfinishedMerge = true;
      notifyListeners();
      throw const AuthException(
        'You are signed in, but the memories from this device could not be '
        'moved across. Try linking again from Settings.',
      );
    }

    await LocalPrefsService.setPendingMerge(
      anonymousUserId: previousId,
      token: grantToken,
    );
    await _runMerge(anonymousUserId: previousId, token: grantToken);
  }

  /// Retries a merge left unfinished by an earlier link attempt. Returns false
  /// when there is nothing pending (or the grant has expired).
  Future<bool> retryPendingMerge() async {
    final pending = await LocalPrefsService.getPendingMerge();
    if (pending == null) {
      hasUnfinishedMerge = false;
      notifyListeners();
      return false;
    }
    await _runMerge(
      anonymousUserId: pending.anonymousUserId,
      token: pending.token,
    );
    return true;
  }

  /// Two retries with backoff — a merge failure is usually a transient network
  /// blip, and the grant is still valid. Throws if it still fails, so the UI
  /// can tell the user their memories have not moved yet.
  Future<void> _runMerge({
    required String anonymousUserId,
    required String token,
  }) async {
    const backoff = [Duration(seconds: 1), Duration(seconds: 3)];

    for (var attempt = 0; attempt <= backoff.length; attempt++) {
      try {
        // Bounded per attempt — this loop's whole point is to retry a
        // transient failure quickly, which an unbounded hang on the first
        // attempt would silently defeat.
        await SupabaseService.mergeAnonymousAccount(
          anonymousUserId: anonymousUserId,
          mergeGrantToken: token,
        ).timeout(AppConstants.dbCallTimeout);
        await LocalPrefsService.clearPendingMerge();
        hasUnfinishedMerge = false;
        notifyListeners();
        return;
      } catch (e) {
        if (attempt == backoff.length) {
          hasUnfinishedMerge = true;
          notifyListeners();
          rethrow;
        }
        await Future<void>.delayed(backoff[attempt]);
      }
    }
  }

  // ── Store-reviewer access ──────────────────────────────────────────────────

  /// Re-reads the reviewer flag. Called off the critical path at startup and
  /// after a user change. A network failure never downgrades an existing
  /// reviewer — losing access mid-review because of a dropped request would be
  /// worse than briefly keeping it.
  Future<void> refreshReviewerStatus() async {
    try {
      final granted =
          await SupabaseService.checkReviewerStatus().timeout(AppConstants.dbCallTimeout);
      if (granted == isReviewer) return;
      isReviewer = granted;
      notifyListeners();
    } catch (e) {
      debugPrint('Could not refresh reviewer status: $e');
    }
  }

  /// Returns false for a wrong passcode; throws only if the check could not be
  /// performed at all.
  Future<bool> submitReviewerPasscode(String code) async {
    final granted =
        await SupabaseService.submitReviewerPasscode(code).timeout(AppConstants.dbCallTimeout);
    if (granted) {
      isReviewer = true;
      notifyListeners();
    }
    return granted;
  }

  // ── Session lifecycle ──────────────────────────────────────────────────────

  /// Signs out and immediately starts a fresh anonymous session. The linked
  /// account keeps everything; signing back in restores it.
  Future<void> signOut() async {
    try {
      await SupabaseService.signOut().timeout(AppConstants.dbCallTimeout);
    } catch (e) {
      // A failed server sign-out still leaves us wanting a clean local slate.
      debugPrint('Sign-out failed, continuing with a fresh session: $e');
    }

    await LocalPrefsService.clearPendingMerge();
    hasUnfinishedMerge = false;
    isReviewer = false;

    _adopt(await SupabaseService.signInAnonymously().timeout(AppConstants.dbCallTimeout));
    notifyListeners();
  }

  /// Permanently deletes the account server-side, then starts a fresh
  /// anonymous session so the app has somewhere to land.
  ///
  /// This also destroys capsules already shared with other people — their
  /// recipients will no longer be able to open them.
  Future<void> deleteAccount() async {
    await SupabaseService.deleteUserAccount();

    // The account is gone, so the current token is dead. Sign out locally
    // (best-effort — the server will reject it) and mint a new identity.
    try {
      await SupabaseService.signOut().timeout(AppConstants.dbCallTimeout);
    } catch (e) {
      debugPrint('Post-deletion sign-out failed (expected): $e');
    }

    // The server-side rows and blobs are gone, but every memory this device
    // ever decrypted still sits in cleartext in the local media cache (see
    // MediaCacheService doc). Deleting the account is a privacy request;
    // leaving that cache behind would quietly ignore it. Best-effort — a
    // failure here must not block the rest of account deletion.
    try {
      await MediaCacheService.clearAll();
    } catch (e) {
      debugPrint('Could not clear the local media cache post-deletion: $e');
    }

    await LocalPrefsService.clearPendingMerge();
    hasUnfinishedMerge = false;
    isReviewer = false;

    _adopt(await SupabaseService.signInAnonymously().timeout(AppConstants.dbCallTimeout));
    notifyListeners();
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _userIdController.close();
    super.dispose();
  }
}

class _OAuthCredential {
  const _OAuthCredential({
    required this.provider,
    required this.idToken,
    required this.accessToken,
    required this.label,
  });

  final supa.OAuthProvider provider;
  final String idToken;
  final String? accessToken;
  final String label;
}
