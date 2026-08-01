// Reconciles the identity-collision case in account linking.
//
// `signInWithIdToken()` merges an Apple/Google identity into the CURRENT
// anonymous session only when that identity has never been used before. If it
// already belongs to a different, pre-existing Supabase user (the recipient
// reinstalled, got a new anonymous id, then signed in with a Google account
// used on a prior install), Supabase signs the client into that existing user
// instead — stranding this device's rows under the now-orphaned anonymous id.
//
// This function runs with the service-role key to reassign those rows and
// delete the orphaned anonymous user.
//
// SECURITY — why `mergeGrantToken` is mandatory
// ---------------------------------------------
// Verifying the caller's JWT proves they own the TARGET account. It proves
// nothing about the SOURCE. Without a source-ownership proof, any
// authenticated user could pass a stranger's anonymous uuid and have this
// function hand them that stranger's capsules and then delete the account
// (IDOR). The client obtains the grant from `request_merge_grant()` while it
// is still the anonymous user — the only moment it can prove it IS that user.
//
// There is deliberately NO "accept a missing token for older clients" branch.
// Such a branch leaves the hole permanently open, which is exactly how this
// class of bug survives in the wild.
//
// Request: POST, Authorization: Bearer <permanent user's session JWT>
//   body: { "anonymousUserId": "<uuid>", "mergeGrantToken": "<hex>" }
import { adminClient, AuthError, requireCallerId } from '../_shared/supabase.ts';
import { handlePreflight, json } from '../_shared/cors.ts';
import { audit } from '../_shared/audit.ts';

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

Deno.serve(async (req: Request) => {
  const preflight = handlePreflight(req);
  if (preflight) return preflight;

  if (req.method !== 'POST') {
    return json(req, { error: 'Method not allowed' }, 405);
  }

  let anonymousUserId: string | undefined;
  let mergeGrantToken: string | undefined;
  try {
    const body = await req.json();
    anonymousUserId = body?.anonymousUserId;
    mergeGrantToken = body?.mergeGrantToken;
  } catch {
    return json(req, { error: 'Invalid JSON body' }, 400);
  }

  if (typeof anonymousUserId !== 'string' || !UUID_RE.test(anonymousUserId)) {
    return json(req, { error: 'anonymousUserId must be a uuid' }, 400);
  }
  if (typeof mergeGrantToken !== 'string' || mergeGrantToken.length === 0) {
    return json(req, { error: 'mergeGrantToken is required' }, 400);
  }

  const admin = adminClient();

  let targetUserId: string;
  try {
    targetUserId = await requireCallerId(req, admin);
  } catch (error) {
    if (error instanceof AuthError) return json(req, { error: error.message }, error.status);
    throw error;
  }

  if (targetUserId === anonymousUserId) {
    // `signInWithIdToken` linked in place — there is nothing to move.
    return json(req, { merged: false, reason: 'same_user' });
  }

  // ── Gate 1: the caller must prove it owned the source account ──────────────
  // p_target records who claimed the grant, which is what lets THIS account —
  // and only this account — retry a merge that failed halfway. Every step of
  // the merge below is idempotent, so replaying it is safe.
  const { data: grantOk, error: grantError } = await admin.rpc('consume_merge_grant', {
    p_token: mergeGrantToken,
    p_expected_source: anonymousUserId,
    p_target: targetUserId,
  });
  if (grantError) {
    console.error('consume_merge_grant failed', grantError);
    return json(req, { error: 'Could not verify the merge grant' }, 500);
  }
  if (grantOk !== true) {
    await audit(admin, targetUserId, 'merge_grant_rejected', { source: anonymousUserId });
    return json(req, { error: 'Source ownership could not be proven' }, 403);
  }

  // ── Gate 2: the source must genuinely be an untouched anonymous account ────
  const { data: sourceData, error: sourceError } =
    await admin.auth.admin.getUserById(anonymousUserId);
  if (sourceError || !sourceData?.user) {
    return json(req, { error: 'Source account not found' }, 404);
  }
  const source = sourceData.user;
  if (source.is_anonymous !== true || (source.identities?.length ?? 0) > 0) {
    // A grant can only be issued by the account itself, so reaching here means
    // the account gained an identity between issue and use. Refuse rather than
    // delete a real, linked account.
    await audit(admin, targetUserId, 'merge_rejected_not_anonymous', { source: anonymousUserId });
    return json(req, { error: 'Source account is not an unlinked anonymous account' }, 409);
  }

  const warnings: string[] = [];

  try {
    // ── Rows owned outright: a plain reassign is safe ───────────────────────
    {
      const { error } = await admin
        .from('time_capsules')
        .update({ creator_id: targetUserId })
        .eq('creator_id', anonymousUserId);
      if (error) warnings.push(`time_capsules: ${error.message}`);
    }

    {
      const { error } = await admin
        .from('feedback')
        .update({ user_id: targetUserId })
        .eq('user_id', anonymousUserId);
      if (error) warnings.push(`feedback: ${error.message}`);
    }

    // ── Rows with UNIQUE(user_id, capsule_id): reassign one by one ──────────
    // On collision the target already tracks that capsule, so its row wins and
    // the source row is dropped. Both rows carry the same encryption_key, so
    // this is lossless.
    for (const table of ['received_capsules', 'saved_memories'] as const) {
      const { data: rows, error: fetchError } = await admin
        .from(table)
        .select('id, capsule_id')
        .eq('user_id', anonymousUserId);
      if (fetchError) {
        warnings.push(`${table} fetch: ${fetchError.message}`);
        continue;
      }

      for (const row of rows ?? []) {
        const { error } = await admin
          .from(table)
          .update({ user_id: targetUserId })
          .eq('id', row.id);
        if (!error) continue;

        if (error.code === '23505') {
          const { error: deleteError } = await admin.from(table).delete().eq('id', row.id);
          if (deleteError) warnings.push(`${table} drop dup ${row.id}: ${deleteError.message}`);
        } else {
          warnings.push(`${table} ${row.id}: ${error.message}`);
        }
      }
    }

    // ── Drop balances ──────────────────────────────────────────────────────
    // One transaction in the database: an unused free drop carries across but
    // is capped at the allowance (linking can never MINT one), purchased packs
    // are always added together since both were paid for, and whichever side
    // holds the later-expiring subscription wins outright — anchor included, so
    // the monthly rollover keeps working.
    //
    // The previous implementation copied only the legacy `free_drop_used`
    // boolean and ignored the counter the gate actually read, so linking
    // silently handed the user their free drop back.
    {
      const { error } = await admin.rpc('merge_drop_balances', {
        p_source: anonymousUserId,
        p_target: targetUserId,
      });
      if (error) warnings.push(`merge_drop_balances: ${error.message}`);
    }

    // ── Storage ────────────────────────────────────────────────────────────
    // We deliberately do NOT move `capsule-media` objects. Their paths are
    // embedded inside the AES-GCM encrypted capsule metadata, which the server
    // cannot decrypt or rewrite — moving the files would break every share link
    // already handed out. Recipients keep reading fine (the bucket's SELECT
    // policy is user-agnostic). We record the inherited prefix instead, so
    // account deletion can still find and purge those objects.
    {
      const { error } = await admin
        .from('user_storage_prefixes')
        .upsert(
          { user_id: targetUserId, prefix: anonymousUserId },
          { onConflict: 'user_id,prefix' },
        );
      if (error) warnings.push(`user_storage_prefixes: ${error.message}`);
    }

    // ── Only now is the source safe to delete ──────────────────────────────
    // On partial failure we leave the anonymous account alive so the data is
    // still reachable and a retry can finish the job. Deleting it here would
    // destroy exactly the rows that failed to move.
    if (warnings.length > 0) {
      console.error('merge-anonymous-account partial failure', warnings);
      await audit(admin, targetUserId, 'anonymous_merge_partial', {
        source: anonymousUserId,
        warnings,
      });
      return json(req, { merged: false, warnings }, 500);
    }

    const { error: deleteError } = await admin.auth.admin.deleteUser(anonymousUserId);
    if (deleteError) {
      // The rows did move, so the merge itself succeeded; only the empty shell
      // account survives. Report success with a warning rather than making the
      // client retry a merge that has already happened.
      await audit(admin, targetUserId, 'anonymous_merge_source_undeleted', {
        source: anonymousUserId,
        detail: deleteError.message,
      });
      return json(req, { merged: true, warnings: [`deleteUser: ${deleteError.message}`] });
    }

    await audit(admin, targetUserId, 'anonymous_merge', { source: anonymousUserId });
    return json(req, { merged: true });
  } catch (error) {
    console.error('merge-anonymous-account failed', error);
    await audit(admin, targetUserId, 'anonymous_merge_failed', {
      source: anonymousUserId,
      detail: String(error),
    });
    return json(req, { error: 'Merge failed', detail: String(error) }, 500);
  }
});
