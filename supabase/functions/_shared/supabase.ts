// Supabase client factories + env validation shared by every Edge Function.
import { createClient, type SupabaseClient } from 'jsr:@supabase/supabase-js@2';

function requireEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) {
    // Fail loudly at first use rather than producing a client that 401s on
    // every call with an opaque message.
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
}

/// Service-role client. Bypasses RLS — never hand this to a code path that
/// hasn't already established which user it is acting for.
export function adminClient(): SupabaseClient {
  return createClient(
    requireEnv('SUPABASE_URL'),
    requireEnv('SUPABASE_SERVICE_ROLE_KEY'),
    { auth: { autoRefreshToken: false, persistSession: false } },
  );
}

export class AuthError extends Error {
  constructor(message: string, readonly status: number) {
    super(message);
  }
}

/// Verifies the caller's `Authorization: Bearer <jwt>` and returns their id.
/// Throws [AuthError] with the status to return.
export async function requireCallerId(req: Request, admin: SupabaseClient): Promise<string> {
  const header = req.headers.get('Authorization');
  if (!header?.startsWith('Bearer ')) {
    throw new AuthError('Missing Authorization header', 401);
  }
  const jwt = header.slice('Bearer '.length);

  const { data, error } = await admin.auth.getUser(jwt);
  if (error || !data?.user) {
    throw new AuthError('Invalid or expired session token', 401);
  }
  return data.user.id;
}
