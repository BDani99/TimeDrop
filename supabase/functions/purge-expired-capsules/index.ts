// Deletes drops created from the free allowance once their retention window
// has passed: a free drop may open at most two months out, and is removed one
// month after it opens.
//
// Paid drops are never touched, and neither is anything a subscriber has kept
// (`saved_memories`) — that condition is re-checked in SQL at delete time, not
// just when the list is built.
//
// WHY THIS IS A FUNCTION AND NOT A pg_cron JOB
// --------------------------------------------
// Postgres cannot reach the Storage API, and deleting `storage.objects` rows
// directly leaves the underlying files in the bucket. Blobs have to go through
// the Storage client, so the job lives here and cron merely triggers it.
//
// ORDER MATTERS
// -------------
// Blobs first, rows second. A failed row delete leaves an unreadable capsule
// (recoverable, visible); a failed blob delete after the row is gone leaves an
// orphan nobody can ever find.
//
// Invoked by pg_cron via pg_net, or by hand. Authenticated with the same
// shared secret style as the RevenueCat webhook.
import { adminClient } from '../_shared/supabase.ts';
import { audit } from '../_shared/audit.ts';

const CAPSULE_BUCKET = 'capsule-media';
const BATCH_LIMIT = 200;

export function timingSafeEqual(a: string, b: string): boolean {
  const ea = new TextEncoder().encode(a);
  const eb = new TextEncoder().encode(b);
  if (ea.length !== eb.length) return false;
  let diff = 0;
  for (let i = 0; i < ea.length; i++) diff |= ea[i] ^ eb[i];
  return diff === 0;
}

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') {
    return json({ error: 'Method not allowed' }, 405);
  }

  const secret = Deno.env.get('PURGE_JOB_SECRET');
  if (!secret) {
    console.error('PURGE_JOB_SECRET is not configured');
    return json({ error: 'Server not configured' }, 500);
  }
  if (!timingSafeEqual(req.headers.get('Authorization') ?? '', secret)) {
    return json({ error: 'Unauthorized' }, 401);
  }

  const admin = adminClient();

  const { data: rows, error } = await admin.rpc('expired_free_capsules', {
    p_limit: BATCH_LIMIT,
  });
  if (error) {
    console.error('expired_free_capsules failed', error);
    return json({ error: 'Could not list expired capsules' }, 500);
  }

  const candidates = (rows ?? []) as Array<{
    capsule_id: string;
    creator_id: string;
    media_paths: string[] | null;
  }>;

  if (candidates.length === 0) {
    return json({ examined: 0, blobsRemoved: 0, capsulesDeleted: 0 });
  }

  const warnings: string[] = [];
  const deletable: string[] = [];
  let blobsRemoved = 0;

  for (const row of candidates) {
    const paths = row.media_paths ?? [];

    // Capsules created before `media_paths` existed have no recorded blobs.
    // Deleting the row would orphan them permanently, so leave them alone and
    // report the count instead of silently leaking storage.
    if (paths.length === 0) {
      warnings.push(`no media_paths recorded: ${row.capsule_id}`);
      continue;
    }

    const { error: removeError } = await admin.storage
      .from(CAPSULE_BUCKET)
      .remove(paths);

    if (removeError) {
      // Keep the row: the next run will retry, and an unreadable-but-present
      // capsule is better than an untraceable pile of blobs.
      warnings.push(`storage ${row.capsule_id}: ${removeError.message}`);
      continue;
    }

    blobsRemoved += paths.length;
    deletable.push(row.capsule_id);
  }

  let capsulesDeleted = 0;
  if (deletable.length > 0) {
    const { data: deleted, error: deleteError } = await admin.rpc(
      'delete_expired_free_capsules',
      { p_ids: deletable },
    );
    if (deleteError) {
      console.error('delete_expired_free_capsules failed', deleteError);
      return json({ error: 'Could not delete expired capsules', blobsRemoved }, 500);
    }
    capsulesDeleted = typeof deleted === 'number' ? deleted : 0;
  }

  const result = {
    examined: candidates.length,
    blobsRemoved,
    capsulesDeleted,
    warnings,
  };
  if (capsulesDeleted > 0 || warnings.length > 0) {
    await audit(admin, null, 'free_capsule_purge', result);
  }
  return json(result);
});

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}
