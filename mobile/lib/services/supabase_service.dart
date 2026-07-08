import 'package:supabase_flutter/supabase_flutter.dart' hide AuthException;

import '../core/constants/supabase_constants.dart';
import '../core/env/env.dart';
import '../core/errors/app_exception.dart';
import '../models/capsule_model.dart';
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

  static Future<void> markFreeDropUsed(String userId) async {
    try {
      await client
          .from(SupabaseConstants.userSettingsTable)
          .update({'free_drop_used': true}).eq('user_id', userId);
    } catch (e) {
      throw CapsuleException('Could not update your account state.', cause: e);
    }
  }

  static Future<void> insertCapsule({
    required String creatorId,
    required String shareId,
    required String encryptedPayload,
    required double latitude,
    required double longitude,
    required DateTime unlockTime,
  }) async {
    try {
      await client.from(SupabaseConstants.timeCapsulesTable).insert({
        'creator_id': creatorId,
        'share_id': shareId,
        'encrypted_payload': encryptedPayload,
        'latitude': latitude,
        'longitude': longitude,
        'unlock_time': unlockTime.toUtc().toIso8601String(),
      });
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        // Unique violation on share_id — caller retries with a new code.
        rethrow;
      }
      throw CapsuleException('Could not save your capsule.', cause: e);
    } catch (e) {
      throw CapsuleException('Could not save your capsule.', cause: e);
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
    } catch (e) {
      throw CapsuleException('Could not find that memory.', cause: e);
    }
  }
}
