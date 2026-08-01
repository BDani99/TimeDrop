// Permanently deletes the calling user's account and everything it owns.
//
// Required by both stores: an app that lets a user create an account must let
// them delete it in-app. The previous client-side implementation only signed
// the user out, which does not satisfy that.
//
// WHAT THIS DESTROYS
// ------------------
// Capsules the user has already shared go too. Their recipients will see
// "memory not found" from that point on. That is the correct answer to a
// deletion request, but the confirmation copy in the app must say so plainly.
//
// Only `deleteUser` is fatal. Everything before it is best-effort and collects
// into `warnings`: a leftover row or blob is recoverable, an auth account that
// refuses to die is not — and returning 500 after a partial purge would leave
// the user unable to retry.
//
// Request: POST, Authorization: Bearer <session JWT>. No body.
import { adminClient, AuthError, requireCallerId } from '../_shared/supabase.ts';
import { handlePreflight, json } from '../_shared/cors.ts';
import { audit } from '../_shared/audit.ts';
import { purgeBucketPrefix } from '../_shared/storage.ts';

const CAPSULE_BUCKET = 'capsule-media';

/// Tables keyed directly by the owning user. Most cascade from `auth.users`
/// anyway; deleting them explicitly makes failures observable in `warnings`
/// instead of silently depending on FK configuration.
const OWNED_TABLES: ReadonlyArray<readonly [table: string, column: string]> = [
  ['time_capsules', 'creator_id'],
  ['saved_memories', 'user_id'],
  ['received_capsules', 'user_id'],
  ['feedback', 'user_id'],
  ['user_storage_prefixes', 'user_id'],
  ['merge_grants', 'source_user_id'],
  ['user_settings', 'user_id'],
];

Deno.serve(async (req: Request) => {
  const preflight = handlePreflight(req);
  if (preflight) return preflight;

  if (req.method !== 'POST') {
    return json(req, { error: 'Method not allowed' }, 405);
  }

  const admin = adminClient();

  let userId: string;
  try {
    userId = await requireCallerId(req, admin);
  } catch (error) {
    if (error instanceof AuthError) return json(req, { error: error.message }, error.status);
    throw error;
  }

  const warnings: string[] = [];
  let objectsRemoved = 0;

  // ── Storage ────────────────────────────────────────────────────────────────
  // The user's own folder, plus every folder inherited from an anonymous
  // account merged into this one (those objects are still theirs; the merge
  // could not move them because their paths live inside the encrypted payload).
  const prefixes = [userId];
  {
    const { data, error } = await admin
      .from('user_storage_prefixes')
      .select('prefix')
      .eq('user_id', userId);
    if (error) {
      warnings.push(`user_storage_prefixes read: ${error.message}`);
    } else {
      for (const row of data ?? []) {
        if (typeof row.prefix === 'string' && !prefixes.includes(row.prefix)) {
          prefixes.push(row.prefix);
        }
      }
    }
  }

  for (const prefix of prefixes) {
    objectsRemoved += await purgeBucketPrefix(admin, CAPSULE_BUCKET, prefix, warnings);
  }

  // ── Rows ───────────────────────────────────────────────────────────────────
  for (const [table, column] of OWNED_TABLES) {
    const { error } = await admin.from(table).delete().eq(column, userId);
    if (error) warnings.push(`${table}: ${error.message}`);
  }

  // ── RevenueCat customer ────────────────────────────────────────────────────
  // Skipped silently when the key isn't configured yet, so this function works
  // before payments are wired up.
  const rcKey = Deno.env.get('REVENUECAT_SECRET_KEY');
  if (rcKey) {
    try {
      const res = await fetch(
        `https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(userId)}`,
        { method: 'DELETE', headers: { Authorization: `Bearer ${rcKey}` } },
      );
      // 404 means there was never a customer record — that is a success here.
      if (!res.ok && res.status !== 404) {
        warnings.push(`revenuecat: HTTP ${res.status}`);
      }
    } catch (error) {
      warnings.push(`revenuecat: ${String(error)}`);
    }
  }

  // ── The one step that must succeed ────────────────────────────────────────
  const { error: deleteError } = await admin.auth.admin.deleteUser(userId);
  if (deleteError) {
    console.error('delete-user-account: deleteUser failed', deleteError, warnings);
    await audit(admin, userId, 'account_delete_failed', {
      detail: deleteError.message,
      warnings,
    });
    return json(req, { error: 'Could not delete your account', detail: deleteError.message }, 500);
  }

  if (warnings.length > 0) {
    console.warn('delete-user-account completed with warnings', userId, warnings);
  }
  await audit(admin, userId, 'account_deleted', { objectsRemoved, warnings });

  return json(req, { deleted: true, objectsRemoved, warnings });
});
