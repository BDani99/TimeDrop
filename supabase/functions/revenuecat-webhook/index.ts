// Receives RevenueCat purchase events and credits the caller's drop balance.
//
// AUTHENTICATION
// --------------
// RevenueCat has no HMAC signature scheme. It sends whatever string you
// configure as the `Authorization` header value — so that string IS the shared
// secret, and it must be long, random, and stored as a Supabase function
// secret (REVENUECAT_WEBHOOK_SECRET). The comparison is timing-safe; `===` on
// a secret leaks its prefix to a patient attacker.
//
// This function must be deployed with verify_jwt = false: the header carries
// RevenueCat's secret, not a Supabase JWT, so the gateway would otherwise
// reject every delivery with a 401 before this code ever runs.
//
// IDEMPOTENCY
// -----------
// RevenueCat retries anything that is not a 2xx. `rc_webhook_events.event_id`
// is the primary key, and the insert is the guard: no row returned means we
// have already processed this delivery, so we answer 200 and stop.
//
// STATUS CODES
// ------------
// 200 for applied / duplicate / ignored / unmapped — anything a retry cannot
// improve. 500 ONLY for genuinely transient failures, so RevenueCat's retry
// ladder is spent on the cases where it helps.
import { adminClient } from '../_shared/supabase.ts';
import { audit } from '../_shared/audit.ts';

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/// Constant-time string comparison. Returns false for a length mismatch, which
/// leaks only the length — unavoidable, and not useful on a random secret.
export function timingSafeEqual(a: string, b: string): boolean {
  const ea = new TextEncoder().encode(a);
  const eb = new TextEncoder().encode(b);
  if (ea.length !== eb.length) return false;
  let diff = 0;
  for (let i = 0; i < ea.length; i++) diff |= ea[i] ^ eb[i];
  return diff === 0;
}

/// RevenueCat's app_user_id is our Supabase uuid only when the client called
/// `Purchases.logIn()`. Before that it is an `$RCAnonymousID:...`, and the real
/// id may show up in `aliases` once the client does log in.
export function resolveUserId(event: Record<string, unknown>): string | null {
  const direct = event.app_user_id;
  if (typeof direct === 'string' && UUID_RE.test(direct)) return direct;

  const aliases = event.aliases;
  if (Array.isArray(aliases)) {
    for (const alias of aliases) {
      if (typeof alias === 'string' && UUID_RE.test(alias)) return alias;
    }
  }
  return null;
}

export function msToIso(value: unknown): string | null {
  if (typeof value !== 'number' || !Number.isFinite(value)) return null;
  return new Date(value).toISOString();
}

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') {
    return json({ error: 'Method not allowed' }, 405);
  }

  const secret = Deno.env.get('REVENUECAT_WEBHOOK_SECRET');
  if (!secret) {
    console.error('REVENUECAT_WEBHOOK_SECRET is not configured');
    return json({ error: 'Server not configured' }, 500);
  }

  const provided = req.headers.get('Authorization') ?? '';
  if (!timingSafeEqual(provided, secret)) {
    return json({ error: 'Unauthorized' }, 401);
  }

  // Read the body exactly once.
  let body: Record<string, unknown>;
  try {
    body = JSON.parse(await req.text());
  } catch {
    return json({ error: 'Invalid JSON body' }, 400);
  }

  const event = (body.event ?? {}) as Record<string, unknown>;
  const eventId = typeof event.id === 'string' ? event.id : null;
  const eventType = typeof event.type === 'string' ? event.type : 'UNKNOWN';
  if (!eventId) {
    return json({ error: 'Missing event.id' }, 400);
  }

  const environment = typeof event.environment === 'string' ? event.environment : null;
  const productId = typeof event.product_id === 'string' ? event.product_id : null;
  const userId = resolveUserId(event);

  const admin = adminClient();

  // Optional guard for production deployments that do not want sandbox noise.
  if (Deno.env.get('RC_ALLOW_SANDBOX') === 'false' && environment === 'SANDBOX') {
    await recordEvent(admin, eventId, eventType, userId, productId, environment, 'ignored', body);
    return json({ status: 'ignored', reason: 'sandbox' });
  }

  // The insert IS the idempotency check.
  const { data: claimed, error: claimError } = await admin
    .from('rc_webhook_events')
    .insert({
      event_id: eventId,
      event_type: eventType,
      app_user_id: userId,
      product_id: productId,
      environment,
      status: 'received',
      payload: body,
    })
    .select('event_id')
    .maybeSingle();

  if (claimError) {
    if (claimError.code === '23505') {
      // Already handled on an earlier delivery.
      return json({ status: 'duplicate' });
    }
    console.error('rc_webhook_events insert failed', claimError);
    // Genuinely transient — let RevenueCat retry.
    return json({ error: 'Could not record the event' }, 500);
  }
  if (!claimed) {
    return json({ status: 'duplicate' });
  }

  if (!userId) {
    // No Supabase user behind this purchase. Retrying will never help — the
    // client has to call Purchases.logIn() and then syncPurchases(). Recorded
    // so the purchase can be reconciled by hand if it never self-heals.
    await setStatus(admin, eventId, 'unmapped_user');
    await audit(admin, null, 'rc_webhook_unmapped_user', { eventId, eventType, productId });
    return json({ status: 'unmapped_user' });
  }

  // One SQL function = one transaction, so balance and ledger cannot diverge.
  const { data: status, error: applyError } = await admin.rpc('rc_apply_event', {
    p_event_id: eventId,
    p_event_type: eventType,
    p_user: userId,
    p_product_id: productId,
    p_purchased_at: msToIso(event.purchased_at_ms),
    p_expires_at: msToIso(event.expiration_at_ms),
  });

  if (applyError) {
    console.error('rc_apply_event failed', eventId, applyError);
    await setStatus(admin, eventId, 'error');
    // Transient by assumption (the database was reachable enough to log) —
    // a retry is worth having.
    return json({ error: 'Could not apply the event' }, 500);
  }

  const resolved = typeof status === 'string' ? status : 'ignored';
  await setStatus(admin, eventId, resolved);

  if (resolved === 'unknown_product') {
    // A missing drop_products row is an operations problem, not a retryable
    // one: answer 200 and make it findable.
    await audit(admin, userId, 'rc_webhook_unknown_product', { eventId, eventType, productId });
  }

  return json({ status: resolved });
});

async function recordEvent(
  admin: ReturnType<typeof adminClient>,
  eventId: string,
  eventType: string,
  userId: string | null,
  productId: string | null,
  environment: string | null,
  status: string,
  payload: unknown,
): Promise<void> {
  await admin.from('rc_webhook_events').upsert(
    {
      event_id: eventId,
      event_type: eventType,
      app_user_id: userId,
      product_id: productId,
      environment,
      status,
      payload,
    },
    { onConflict: 'event_id' },
  );
}

async function setStatus(
  admin: ReturnType<typeof adminClient>,
  eventId: string,
  status: string,
): Promise<void> {
  const { error } = await admin
    .from('rc_webhook_events')
    .update({ status })
    .eq('event_id', eventId);
  if (error) console.warn('Could not update webhook event status', eventId, error);
}

function json(body: unknown, status = 200): Response {
  // No CORS headers: this endpoint is only ever called server-to-server.
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}
