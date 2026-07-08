// Reconciles the identity-collision case in Sprint 3 account linking:
// `signInWithIdToken()` on the client merges an Apple/Google identity into
// the CURRENT anonymous session only when that identity has never been used
// before. If the identity already belongs to a different, pre-existing
// Supabase user (e.g. the recipient reinstalled the app, got a new
// anonymous id, then signed in with a Google account used on a prior
// install), Supabase instead signs the client into that existing permanent
// user — stranding the anonymous user's `time_capsules`/`saved_memories`
// rows under the old, now-orphaned anonymous id.
//
// This function runs with the service-role key (bypasses RLS) to reassign
// those rows to the permanent account and delete the orphaned anonymous
// user. It must be called by the client AFTER `signInWithIdToken()`
// succeeds, passing along the anonymous user id captured BEFORE that call.
//
// Request: POST, Authorization: Bearer <permanent user's session JWT>
//   body: { "anonymousUserId": "<uuid>" }
import { createClient } from 'jsr:@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') {
    return json({ error: 'Method not allowed' }, 405);
  }

  const authHeader = req.headers.get('Authorization');
  if (!authHeader?.startsWith('Bearer ')) {
    return json({ error: 'Missing Authorization header' }, 401);
  }
  const callerJwt = authHeader.replace('Bearer ', '');

  let anonymousUserId: string | undefined;
  try {
    const body = await req.json();
    anonymousUserId = body.anonymousUserId;
  } catch {
    return json({ error: 'Invalid JSON body' }, 400);
  }
  if (!anonymousUserId || typeof anonymousUserId !== 'string') {
    return json({ error: 'anonymousUserId is required' }, 400);
  }

  const adminClient = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  // Verify the caller's JWT and use its subject as the permanent user id —
  // never trust a client-supplied "new user id", only the anonymous one
  // being merged away.
  const { data: callerData, error: callerError } = await adminClient.auth.getUser(callerJwt);
  if (callerError || !callerData?.user) {
    return json({ error: 'Invalid or expired session token' }, 401);
  }
  const permanentUserId = callerData.user.id;

  if (permanentUserId === anonymousUserId) {
    // Nothing to merge — signInWithIdToken already linked in place.
    return json({ merged: false, reason: 'same user' });
  }

  try {
    const { error: capsulesError } = await adminClient
      .from('time_capsules')
      .update({ creator_id: permanentUserId })
      .eq('creator_id', anonymousUserId);
    if (capsulesError) throw capsulesError;

    // saved_memories has a UNIQUE(user_id, capsule_id) constraint — rows
    // that would collide with an existing saved memory on the permanent
    // account are left on the anonymous user and cleaned up by the
    // subsequent deleteUser() cascade instead of erroring the whole merge.
    const { data: anonSaved, error: fetchSavedError } = await adminClient
      .from('saved_memories')
      .select('id, capsule_id, encryption_key, saved_at')
      .eq('user_id', anonymousUserId);
    if (fetchSavedError) throw fetchSavedError;

    for (const row of anonSaved ?? []) {
      await adminClient
        .from('saved_memories')
        .update({ user_id: permanentUserId })
        .eq('id', row.id)
        .then(({ error }: { error: unknown }) => {
          // Ignore unique-violation collisions; the anonymous row is
          // deleted along with the user below regardless.
          if (error) console.warn('saved_memories reassign skipped', row.id, error);
        });
    }

    // Carry over free_drop_used so linking doesn't grant a bonus free drop.
    const { data: anonSettings } = await adminClient
      .from('user_settings')
      .select('free_drop_used')
      .eq('user_id', anonymousUserId)
      .maybeSingle();
    if (anonSettings?.free_drop_used) {
      const { error: settingsError } = await adminClient
        .from('user_settings')
        .update({ free_drop_used: true })
        .eq('user_id', permanentUserId);
      if (settingsError) throw settingsError;
    }

    // Cascades (FK on delete cascade) to remaining user_settings /
    // time_capsules / saved_memories rows still owned by the anonymous id.
    const { error: deleteError } = await adminClient.auth.admin.deleteUser(anonymousUserId);
    if (deleteError) throw deleteError;

    return json({ merged: true });
  } catch (error) {
    console.error('merge-anonymous-account failed', error);
    return json({ error: 'Merge failed', detail: String(error) }, 500);
  }
});

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}
