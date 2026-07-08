import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;

import '../core/constants/supabase_constants.dart';
import '../core/errors/app_exception.dart';
import '../services/supabase_service.dart';

enum AuthStatus { unknown, anonymous, linked }

/// Handles anonymous-first sign-in (Sprint 0) and Apple/Google account
/// linking (Sprint 3). Linking is built against Supabase's `linkIdentity()`
/// API and fails gracefully — surfaced as an [AuthException] — if OAuth
/// providers aren't configured in the Supabase dashboard yet.
class AuthProvider extends ChangeNotifier {
  AuthStatus status = AuthStatus.unknown;
  supa.User? user;

  Future<void> bootstrap() async {
    final existing = SupabaseService.currentUser;
    if (existing != null) {
      user = existing;
      status = existing.isAnonymous ? AuthStatus.anonymous : AuthStatus.linked;
      notifyListeners();
      return;
    }

    final signedInUser = await SupabaseService.signInAnonymously();
    user = signedInUser;
    status = AuthStatus.anonymous;
    notifyListeners();
  }

  String? get userId => user?.id;
  bool get isLinked => status == AuthStatus.linked;

  Future<void> linkGoogle() async {
    try {
      final googleSignIn = GoogleSignIn();
      final googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        throw const AuthException('Google sign-in was cancelled.');
      }
      final googleAuth = await googleUser.authentication;
      final idToken = googleAuth.idToken;
      if (idToken == null) {
        throw const AuthException('Google sign-in did not return a token.');
      }

      // `signInWithIdToken` merges into the current anonymous session when
      // this Google identity has never been used before (Supabase's native
      // linking behavior). If it was previously used on another install,
      // Supabase issues a *different* existing user instead — the
      // `merge-anonymous-account` Edge Function (Sprint 3) reconciles that
      // collision case by reassigning this device's capsule rows.
      final previousAnonymousId = user?.id;
      final response = await SupabaseService.client.auth.signInWithIdToken(
        provider: supa.OAuthProvider.google,
        idToken: idToken,
        accessToken: googleAuth.accessToken,
      );
      user = response.user;
      status = AuthStatus.linked;
      await _reconcileIdentityCollision(previousAnonymousId);
      notifyListeners();
    } catch (e) {
      throw AuthException(
        'Could not link your Google account. It may not be configured yet.',
        cause: e,
      );
    }
  }

  Future<void> linkApple() async {
    try {
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

      final previousAnonymousId = user?.id;
      final response = await SupabaseService.client.auth.signInWithIdToken(
        provider: supa.OAuthProvider.apple,
        idToken: idToken,
      );
      user = response.user;
      status = AuthStatus.linked;
      await _reconcileIdentityCollision(previousAnonymousId);
      notifyListeners();
    } catch (e) {
      throw AuthException(
        'Could not link your Apple account. It may not be configured yet.',
        cause: e,
      );
    }
  }

  /// Calls the `merge-anonymous-account` Edge Function when
  /// `signInWithIdToken` landed on a pre-existing permanent user instead of
  /// merging into the current anonymous session (i.e. this OAuth identity
  /// was already used on a previous install) — reassigns this device's
  /// capsule rows from the orphaned anonymous id to the permanent account.
  /// A failure here is non-fatal to the linking flow itself (the user is
  /// already signed in); it's logged rather than surfaced as a blocking
  /// error, since the primary linking action already succeeded.
  Future<void> _reconcileIdentityCollision(String? previousAnonymousId) async {
    final newUserId = user?.id;
    if (previousAnonymousId == null || newUserId == null) return;
    if (previousAnonymousId == newUserId) return;

    try {
      final session = SupabaseService.client.auth.currentSession;
      if (session == null) return;
      await SupabaseService.client.functions.invoke(
        SupabaseConstants.mergeAnonymousAccountFunction,
        body: {'anonymousUserId': previousAnonymousId},
        headers: {'Authorization': 'Bearer ${session.accessToken}'},
      );
    } catch (e) {
      debugPrint('merge-anonymous-account reconciliation failed: $e');
    }
  }

  Future<void> deleteAccount() async {
    try {
      // Row deletion cascades via FK `on delete cascade`; the auth.users row
      // itself requires the service-role key, so this triggers a server-side
      // Edge Function in a full deployment. For now, sign the user out
      // locally — full remote deletion is a Sprint 3 follow-up once the
      // Edge Function is deployed.
      await SupabaseService.client.auth.signOut();
      user = null;
      status = AuthStatus.unknown;
      notifyListeners();
    } catch (e) {
      throw AuthException('Could not delete your account.', cause: e);
    }
  }
}
