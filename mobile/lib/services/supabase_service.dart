import 'package:supabase_flutter/supabase_flutter.dart' hide AuthException;

import '../core/constants/supabase_constants.dart';
import '../core/env/env.dart';
import '../core/errors/app_exception.dart';
import '../models/capsule_model.dart';
import '../models/drop_state_model.dart';
import '../models/received_capsule_model.dart';
import '../models/user_settings_model.dart';

/// Thin, typed wrapper around the Supabase client. Every method here maps
/// Supabase's own exceptions into an [AppException] subtype so callers never
/// need to know about `PostgrestException`/`AuthException` etc.
class SupabaseService {
  SupabaseService._();

  static SupabaseClient get client => Supabase.instance.client;

  static Future<void> initialize() async {
    await Supabase.initialize(
      url: Env.supabaseUrl,
      publishableKey: Env.supabaseAnonKey,
    );
  }

  static User? get currentUser => client.auth.currentUser;
  static bool get isSignedIn => currentUser != null;

  static Future<User> signInAnonymously() async {
    try {
      final response = await client.auth.signInAnonymously();
      final user = response.user;
      if (user == null) {
        throw const AuthException('Anonymous sign-in did not return a user.');
      }
      return user;
    } catch (e) {
      throw AuthException('Could not sign in anonymously.', cause: e);
    }
  }

  static Future<void> signOut() async {
    try {
      await client.auth.signOut();
    } catch (e) {
      throw AuthException('Could not sign you out.', cause: e);
    }
  }

  /// Issues a single-use, 15-minute token proving the caller owns the account
  /// it is called from. Must be obtained BEFORE the OAuth round trip, while the
  /// session is still the anonymous user — it is the only proof
  /// [mergeAnonymousAccount] will accept that the caller owned the source.
  static Future<String> requestMergeGrant() async {
    try {
      final token = await client.rpc(SupabaseConstants.requestMergeGrantRpc);
      if (token is! String || token.isEmpty) {
        throw const AuthException('Could not prepare the account merge.');
      }
      return token;
    } catch (e) {
      if (e is AuthException) rethrow;
      throw AuthException('Could not prepare the account merge.', cause: e);
    }
  }

  /// Moves everything owned by [anonymousUserId] onto the currently signed-in
  /// account, then deletes the anonymous account.
  ///
  /// Throws on failure — the caller MUST surface it. Reporting success here
  /// when the move failed would leave the user believing memories carried over
  /// while they are in fact stranded on an account they can no longer reach.
  static Future<void> mergeAnonymousAccount({
    required String anonymousUserId,
    required String mergeGrantToken,
  }) async {
    final session = client.auth.currentSession;
    if (session == null) {
      throw const AuthException('Your session ended before the merge could run.');
    }

    try {
      final response = await client.functions.invoke(
        SupabaseConstants.mergeAnonymousAccountFunction,
        body: {
          'anonymousUserId': anonymousUserId,
          'mergeGrantToken': mergeGrantToken,
        },
        headers: {'Authorization': 'Bearer ${session.accessToken}'},
      );

      final data = response.data;
      final merged = data is Map && data['merged'] == true;
      final sameUser = data is Map && data['reason'] == 'same_user';
      if (!merged && !sameUser) {
        throw AuthException(
          'Your memories could not be moved to the linked account.',
          cause: data,
        );
      }
    } catch (e) {
      if (e is AuthException) rethrow;
      throw AuthException(
        'Your memories could not be moved to the linked account.',
        cause: e,
      );
    }
  }

  /// Permanently deletes the signed-in account, its rows and its media.
  /// Irreversible, and it also destroys capsules already shared with others.
  static Future<void> deleteUserAccount() async {
    final session = client.auth.currentSession;
    if (session == null) {
      throw const AuthException('You need to be signed in to delete your account.');
    }

    try {
      final response = await client.functions.invoke(
        SupabaseConstants.deleteUserAccountFunction,
        body: const <String, dynamic>{},
        headers: {'Authorization': 'Bearer ${session.accessToken}'},
      );
      final data = response.data;
      if (data is! Map || data['deleted'] != true) {
        throw AuthException('Could not delete your account.', cause: data);
      }
    } catch (e) {
      if (e is AuthException) rethrow;
      throw AuthException('Could not delete your account.', cause: e);
    }
  }

  // ── Drop ledger ────────────────────────────────────────────────────────────

  /// Translates the ledger RPCs' custom SQLSTATEs into typed exceptions.
  ///
  /// Classifying by `PostgrestException.code` is the whole reason those
  /// SQLSTATEs exist: matching on message substrings misclassifies unrelated
  /// failures (a network error whose text happens to contain "auth", say) and
  /// silently changes meaning whenever a message is reworded.
  static Never _mapDropRpcError(PostgrestException e) {
    switch (e.code) {
      case 'TD001':
        throw const DropQuotaException("You're out of drops.");
      case 'TD002':
        throw const AuthException('You need to be signed in to do that.');
      case 'TD003':
        throw const DropQuotaException(
          'A free drop can only open up to two months from now. '
          'Get more drops to send further into the future.',
          canBuyMore: false,
        );
      case 'TD004':
        throw const CapsuleException('That memory could not be found.');
      case 'TD005':
        throw const CapsuleException(
          'Too many failed attempts. Wait an hour, then try again.',
        );
      default:
        assert(() {
          // Loud in debug so a new server-side code cannot quietly degrade
          // into the generic message.
          // ignore: avoid_print
          print('Unmapped drop RPC SQLSTATE: ${e.code} — ${e.message}');
          return true;
        }());
        throw CapsuleException('Could not save your capsule.', cause: e);
    }
  }

  /// Idempotent safety net for accounts created before the ledger existed.
  static Future<void> ensureDropBalance() async {
    try {
      await client.rpc(SupabaseConstants.ensureOwnDropBalanceRpc);
    } on PostgrestException catch (e) {
      _mapDropRpcError(e);
    } catch (e) {
      throw CapsuleException('Could not load your drop balance.', cause: e);
    }
  }

  static Future<DropState> fetchDropState() async {
    try {
      final rows = await client.rpc(SupabaseConstants.getDropStateRpc);
      final list = rows as List;
      if (list.isEmpty) {
        throw const CapsuleException('Could not load your drop balance.');
      }
      return DropState.fromJson(list.first as Map<String, dynamic>);
    } on PostgrestException catch (e) {
      _mapDropRpcError(e);
    } catch (e) {
      if (e is AppException) rethrow;
      throw CapsuleException('Could not load your drop balance.', cause: e);
    }
  }

  /// Creates the capsule row AND debits a drop in a single transaction.
  ///
  /// Replaces the old two-call flow (insert + best-effort counter bump), which
  /// could leave the two disagreeing. A `share_id` collision still surfaces as
  /// 23505 so the caller's retry loop works unchanged — and the debit rolls
  /// back with it.
  static Future<Map<String, dynamic>> createPendingCapsule({
    required String shareId,
    required double latitude,
    required double longitude,
    required DateTime unlockTime,
    String? codeUnlockKey,
  }) async {
    try {
      final rows = await client.rpc(
        SupabaseConstants.createPendingCapsuleRpc,
        params: {
          'p_share_id': shareId,
          'p_latitude': latitude,
          'p_longitude': longitude,
          'p_unlock_time': unlockTime.toUtc().toIso8601String(),
          // Non-null ONLY when the sender chose to let the bare code open this
          // drop. Sending the key here hands the server the ability to decrypt
          // this one memory — see migration 0030.
          'p_code_unlock_key': codeUnlockKey,
        },
      );
      final list = rows as List;
      if (list.isEmpty) {
        throw const CapsuleException('Could not save your capsule.');
      }
      return list.first as Map<String, dynamic>;
    } on PostgrestException catch (e) {
      // Unique violation on share_id — caller retries with a new code.
      if (e.code == '23505') rethrow;
      _mapDropRpcError(e);
    } catch (e) {
      if (e is AppException) rethrow;
      throw CapsuleException('Could not save your capsule.', cause: e);
    }
  }

  /// Deletes a capsule and refunds its drop when it never reached 'ready'.
  static Future<Map<String, dynamic>> discardCapsule(String capsuleId) async {
    try {
      final rows = await client.rpc(
        SupabaseConstants.discardCapsuleRpc,
        params: {'p_capsule_id': capsuleId},
      );
      final list = rows as List;
      if (list.isEmpty) {
        throw const CapsuleException('Could not discard your capsule.');
      }
      return list.first as Map<String, dynamic>;
    } on PostgrestException catch (e) {
      _mapDropRpcError(e);
    } catch (e) {
      if (e is AppException) rethrow;
      throw CapsuleException('Could not discard your capsule.', cause: e);
    }
  }

  // ── Store-reviewer access ──────────────────────────────────────────────────

  /// Whether the signed-in account has been granted reviewer status. Reads the
  /// flag directly — `reviewer_flags` exposes a select-own policy.
  static Future<bool> checkReviewerStatus() async {
    // Without a session there is nothing to check. Passing an empty string to
    // a uuid column would raise a Postgres parse error that reads like a real
    // failure.
    final userId = currentUser?.id;
    if (userId == null) return false;

    try {
      final row = await client
          .from(SupabaseConstants.reviewerFlagsTable)
          .select('is_reviewer')
          .eq('user_id', userId)
          .maybeSingle();
      return row?['is_reviewer'] as bool? ?? false;
    } catch (e) {
      throw AuthException('Could not check reviewer status.', cause: e);
    }
  }

  /// Submits a candidate passcode. The real one never ships in the binary — the
  /// RPC compares against a salted hash the client cannot read, enforces a
  /// 5-per-24h attempt limit, and honours a server-side kill switch.
  ///
  /// Returns false for a wrong code; throws only on a transport failure, so the
  /// UI can tell "wrong passcode" from "no network".
  static Future<bool> submitReviewerPasscode(String code) async {
    try {
      final result = await client.rpc(
        SupabaseConstants.validateReviewerPasscodeRpc,
        params: {'p_code': code},
      );
      return result == true;
    } catch (e) {
      throw AuthException('Could not verify the passcode.', cause: e);
    }
  }

  static Future<UserSettingsModel> fetchUserSettings(String userId) async {
    try {
      final row = await client
          .from(SupabaseConstants.userSettingsTable)
          .select()
          .eq('user_id', userId)
          .single();
      return UserSettingsModel.fromJson(row);
    } catch (e) {
      throw AuthException('Could not load account settings.', cause: e);
    }
  }

  static Future<void> completeOnboarding({
    required String userId,
    Map<String, dynamic>? answers,
  }) async {
    try {
      await client.from(SupabaseConstants.userSettingsTable).update({
        'onboarding_completed': true,
        'onboarding_answers': ?answers,
      }).eq('user_id', userId);
    } catch (e) {
      throw AuthException('Could not save your onboarding.', cause: e);
    }
  }

  /// Reads the runtime `system_settings` key/value pairs as a numeric map.
  static Future<Map<String, double>> fetchSystemSettings() async {
    try {
      final rows = await client
          .from(SupabaseConstants.systemSettingsTable)
          .select('key, value');
      final result = <String, double>{};
      for (final row in rows as List) {
        final map = row as Map<String, dynamic>;
        final key = map['key'] as String?;
        final value = map['value'];
        if (key != null && value != null) {
          result[key] = (value as num).toDouble();
        }
      }
      return result;
    } catch (e) {
      throw CapsuleException('Could not load app settings.', cause: e);
    }
  }

  /// Background-upload completion: attach the encrypted payload and flip the
  /// status (to 'ready' on success, or 'failed').
  /// Throws [CapsuleException] if the row wasn't found or RLS blocked the
  /// update (so callers don't silently leave the row in a stale state).
  static Future<void> updateCapsulePayload({
    required String capsuleId,
    String? encryptedPayload,
    List<String>? mediaPaths,
    required String status,
  }) async {
    try {
      final rows = await client
          .from(SupabaseConstants.timeCapsulesTable)
          .update({
            'encrypted_payload': ?encryptedPayload,
            // Plain copy of the blob paths that are also inside the encrypted
            // payload — the server cannot read those, so this is its only way
            // to purge a capsule's storage objects later.
            'media_paths': ?mediaPaths,
            'status': status,
          })
          .eq('id', capsuleId)
          .select('id');
      if ((rows as List).isEmpty) {
        throw CapsuleException(
          'Could not update capsule status to "$status" — '
          'the row may not exist or auth context has changed.',
        );
      }
    } catch (e) {
      if (e is CapsuleException) rethrow;
      throw CapsuleException('Could not finalize your capsule.', cause: e);
    }
  }

  static Future<List<CapsuleModel>> fetchSentCapsules(String creatorId) async {
    try {
      final rows = await client
          .from(SupabaseConstants.timeCapsulesTable)
          .select()
          .eq('creator_id', creatorId)
          .order('created_at', ascending: false);
      return (rows as List)
          .map((row) => CapsuleModel.fromJson(row as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw CapsuleException('Could not load your sent memories.', cause: e);
    }
  }

  /// Returns only rows with status = 'pending' for the given creator — used by
  /// [CapsuleProvider.reconcileStuckCapsules] to detect orphaned rows.
  static Future<List<CapsuleModel>> fetchPendingCapsules(String creatorId) async {
    try {
      final rows = await client
          .from(SupabaseConstants.timeCapsulesTable)
          .select()
          .eq('creator_id', creatorId)
          .eq('status', 'pending')
          .order('created_at', ascending: false);
      return (rows as List)
          .map((row) => CapsuleModel.fromJson(row as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw CapsuleException('Could not check pending capsules.', cause: e);
    }
  }

  /// Persists a reverse-geocoded city label for a sent capsule (best effort —
  /// Home fills this lazily so it isn't recomputed each load). Mirrors
  /// [updateReceivedCapsuleCity]; relies on the `time_capsules_update_own`
  /// RLS policy (creator-scoped update).
  static Future<void> updateSentCapsuleCity({
    required String capsuleId,
    required String city,
  }) async {
    try {
      await client
          .from(SupabaseConstants.timeCapsulesTable)
          .update({'city': city})
          .eq('id', capsuleId);
    } catch (e) {
      throw CapsuleException('Could not update your capsule.', cause: e);
    }
  }

  /// Updates unlock time / pin for a capsule the current user created, and
  /// syncs denormalized fields on every `received_capsules` row for that id.
  static Future<void> updateSentCapsuleMeta({
    required String capsuleId,
    required DateTime unlockTime,
    required double latitude,
    required double longitude,
    String? city,
  }) async {
    try {
      await client.rpc(
        SupabaseConstants.updateSentCapsuleMetaRpc,
        params: {
          'p_capsule_id': capsuleId,
          'p_unlock_time': unlockTime.toUtc().toIso8601String(),
          'p_latitude': latitude,
          'p_longitude': longitude,
          'p_city': city,
        },
      );
    } catch (e) {
      throw CapsuleException('Could not update this memory.', cause: e);
    }
  }

  /// Sprint 3 "Keep this memory forever" — see migration
  /// `0005_saved_memories.sql` for the documented Zero-Knowledge trade-off
  /// of persisting the raw encryption key server-side for opted-in saves.
  static Future<void> saveMemory({
    required String userId,
    required String capsuleId,
    required String encryptionKey,
  }) async {
    try {
      await client.from(SupabaseConstants.savedMemoriesTable).upsert(
        {
          'user_id': userId,
          'capsule_id': capsuleId,
          'encryption_key': encryptionKey,
        },
        onConflict: 'user_id,capsule_id',
      );
    } catch (e) {
      throw CapsuleException('Could not save this memory.', cause: e);
    }
  }

  static Future<CapsuleModel?> fetchCapsuleByShareId(String shareId) async {
    try {
      final rows = await client.rpc(
        SupabaseConstants.getCapsuleByShareIdRpc,
        params: {'p_share_id': shareId},
      );
      final list = rows as List;
      if (list.isEmpty) return null;
      return CapsuleModel.fromJson(list.first as Map<String, dynamic>);
    } on PostgrestException catch (e) {
      // The lookup is rate limited on misses (migration 0026), so a throttled
      // caller needs to be told to wait rather than shown "not found" — which
      // would read as "your link is broken".
      _mapDropRpcError(e);
    } catch (e) {
      throw CapsuleException('Could not find that memory.', cause: e);
    }
  }

  /// Tracks a capsule the current user has resolved as a *recipient* — see
  /// `received_capsules` migration for why fields are denormalized here
  /// rather than joined. [encryptionKey] is omitted from the payload (not
  /// sent as an explicit null) when unknown, so an `ON CONFLICT` upsert
  /// never overwrites an already-known key with a missing one.
  static Future<void> upsertReceivedCapsule({
    required String userId,
    required String capsuleId,
    required String shareId,
    required DateTime unlockTime,
    required double latitude,
    required double longitude,
    String? encryptionKey,
    String? fromName,
    DateTime? capsuleCreatedAt,
  }) async {
    try {
      final payload = <String, dynamic>{
        'user_id': userId,
        'capsule_id': capsuleId,
        'share_id': shareId,
        'unlock_time': unlockTime.toUtc().toIso8601String(),
        'latitude': latitude,
        'longitude': longitude,
        'encryption_key': ?encryptionKey,
        'from_name': ?fromName,
        'capsule_created_at': capsuleCreatedAt?.toUtc().toIso8601String(),
      };
      await client
          .from(SupabaseConstants.receivedCapsulesTable)
          .upsert(payload, onConflict: 'user_id,capsule_id');
    } catch (e) {
      throw CapsuleException('Could not save this memory to your gallery.', cause: e);
    }
  }

  /// Persists a reverse-geocoded city label for a received capsule (best
  /// effort — Vault fills this lazily so it isn't recomputed each load).
  static Future<void> updateReceivedCapsuleCity({
    required String userId,
    required String capsuleId,
    required String city,
  }) async {
    try {
      await client
          .from(SupabaseConstants.receivedCapsulesTable)
          .update({'city': city})
          .eq('user_id', userId)
          .eq('capsule_id', capsuleId);
    } catch (_) {
      // Non-fatal — the city is a cosmetic cache.
    }
  }

  static Future<void> updateUserDisplayName({
    required String userId,
    required String displayName,
  }) async {
    try {
      await client
          .from(SupabaseConstants.userSettingsTable)
          .update({'display_name': displayName})
          .eq('user_id', userId);
    } catch (e) {
      throw AuthException('Could not save your name.', cause: e);
    }
  }

  static Future<void> markReceivedCapsuleUnlocked({
    required String userId,
    required String capsuleId,
  }) async {
    try {
      await client
          .from(SupabaseConstants.receivedCapsulesTable)
          .update({'unlocked_at': DateTime.now().toUtc().toIso8601String()})
          .eq('user_id', userId)
          .eq('capsule_id', capsuleId);
    } catch (e) {
      throw CapsuleException('Could not update your gallery.', cause: e);
    }
  }

  static Future<void> markReceivedCapsuleViewed({
    required String userId,
    required String capsuleId,
    double? unlockDistanceMeters,
  }) async {
    try {
      await client
          .from(SupabaseConstants.receivedCapsulesTable)
          .update({
            'is_viewed': true,
            'viewed_at': DateTime.now().toUtc().toIso8601String(),
            // Only sent when we actually measured it — a replay must not
            // overwrite the real reading with a null.
            'unlock_distance_meters': ?unlockDistanceMeters,
          })
          .eq('user_id', userId)
          .eq('capsule_id', capsuleId);
    } catch (e) {
      throw CapsuleException('Could not update your gallery.', cause: e);
    }
  }

  static Future<List<ReceivedCapsuleModel>> fetchReceivedCapsules(String userId) async {
    try {
      final rows = await client
          .from(SupabaseConstants.receivedCapsulesTable)
          .select()
          .eq('user_id', userId)
          .order('first_seen_at', ascending: false);
      return (rows as List)
          .map((row) => ReceivedCapsuleModel.fromJson(row as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw CapsuleException('Could not load your gallery.', cause: e);
    }
  }

  /// Inserts a feedback / bug-report row.
  /// [type] must be one of: 'bug', 'feedback', 'other'.
  static Future<void> submitFeedback({
    required String userId,
    required String type,
    required String message,
    required String appVersion,
    required String platform,
  }) async {
    try {
      await client.from(SupabaseConstants.feedbackTable).insert({
        'user_id': userId,
        'type': type,
        'message': message.trim(),
        'app_version': appVersion,
        'platform': platform,
      });
    } catch (e) {
      throw FeedbackException('Could not send your feedback. Please try again.', cause: e);
    }
  }
}

