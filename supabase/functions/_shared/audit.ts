import type { SupabaseClient } from 'jsr:@supabase/supabase-js@2';

/// Best-effort append to `audit_log`. Never throws: an audit write failing must
/// not turn a successful account merge or deletion into an error response.
export async function audit(
  admin: SupabaseClient,
  userId: string | null,
  action: string,
  metadata: Record<string, unknown> = {},
): Promise<void> {
  try {
    await admin.from('audit_log').insert({ user_id: userId, action, metadata });
  } catch (error) {
    console.warn('audit_log write failed', action, error);
  }
}
