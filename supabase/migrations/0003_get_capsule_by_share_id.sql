-- Narrow, single-row lookup function for the Recipient/Radar flow.
-- SECURITY DEFINER bypasses the owner-only RLS policy on time_capsules, but
-- only ever returns the one row matching an exact high-entropy share_id
-- (36^6 ≈ 2.18B combinations), never a scan — this is the actual security
-- boundary for "public by share_id" reads.
--
-- Defense in depth: encrypted_payload is withheld (returned NULL) until
-- unlock_time has passed, even though it's only ciphertext; this avoids
-- letting a recipient's device pull the ciphertext blob ahead of the
-- countdown finishing, and keeps storage egress aligned with the unlock UX.
create or replace function public.get_capsule_by_share_id(p_share_id text)
returns table (
  id                uuid,
  share_id          text,
  latitude          float8,
  longitude         float8,
  unlock_time       timestamptz,
  created_at        timestamptz,
  encrypted_payload text
)
language sql
security definer
set search_path = public
stable
as $$
  select
    tc.id,
    tc.share_id,
    tc.latitude,
    tc.longitude,
    tc.unlock_time,
    tc.created_at,
    case when now() >= tc.unlock_time then tc.encrypted_payload else null end
  from public.time_capsules tc
  where tc.share_id = p_share_id
  limit 1;
$$;

revoke all on function public.get_capsule_by_share_id(text) from public;
revoke all on function public.get_capsule_by_share_id(text) from anon;
grant execute on function public.get_capsule_by_share_id(text) to authenticated;

-- NOTE: `anon` role is explicitly revoked because the mobile app always signs
-- in anonymously via Supabase Auth first (Sprint 0), so every real caller
-- holds an `authenticated` JWT (with an `is_anonymous: true` claim) — this
-- closes off unauthenticated scraping entirely.
