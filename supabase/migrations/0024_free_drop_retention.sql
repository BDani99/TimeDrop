-- Retention for drops created from the FREE allowance.
--
-- THE RULE
-- --------
-- A free drop may open at most two months out (enforced in
-- create_pending_capsule, migration 0020). One month after it opens, the
-- capsule is deleted — three months end to end, with a full month for the
-- recipient to watch it.
--
-- Paid drops are never touched. Neither is anything a subscriber has kept.
--
-- WHY `media_paths`
-- -----------------
-- The storage paths live INSIDE the AES-GCM encrypted metadata payload, which
-- the server cannot decrypt. Deleting only the row would leave every blob
-- orphaned in the bucket forever, so the retention rule would free no storage
-- at all — the point of having it.
--
-- Recording the paths in a plain column costs nothing in confidentiality: a
-- path is `{uid}/{uuid}.enc`, the blobs stay end-to-end encrypted, and the
-- service role can already enumerate the bucket. Account deletion benefits
-- from the same column.

alter table public.time_capsules
  add column if not exists media_paths text[];

comment on column public.time_capsules.media_paths is
  'Storage object paths for this capsule, so the server can purge blobs whose '
  'paths it cannot read out of the encrypted payload. Not secret.';

-- ── Selecting what to purge ──────────────────────────────────────────────────
-- Returns capsules that are past their retention window. Read-only: the
-- deleting is done by the purge-expired-capsules Edge Function, which removes
-- the storage objects first (SQL cannot reach the Storage API, and deleting
-- `storage.objects` rows directly would leave the underlying files behind).
create or replace function public.expired_free_capsules(p_limit int default 200)
returns table (capsule_id uuid, creator_id uuid, media_paths text[])
language sql
security definer
set search_path = public
stable
as $$
  select t.id, t.creator_id, t.media_paths
    from public.time_capsules t
   where t.funding_bucket = 'free'
     and t.unlock_time < now() - interval '1 month'
     -- A memory somebody chose to keep outlives the retention rule. Keeping is
     -- a paid feature, and pulling it out from under them would be worse than
     -- holding the storage.
     and not exists (
       select 1 from public.saved_memories s where s.capsule_id = t.id
     )
   order by t.unlock_time
   limit p_limit;
$$;

revoke all on function public.expired_free_capsules(int) from public, anon, authenticated;
grant execute on function public.expired_free_capsules(int) to service_role;

-- Deletes the rows once their blobs are gone. Re-checks the conditions rather
-- than trusting the caller's list, so a stale id from a long-running purge can
-- never take out a capsule that has since been kept.
create or replace function public.delete_expired_free_capsules(p_ids uuid[])
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_deleted int;
begin
  delete from public.time_capsules t
   where t.id = any(p_ids)
     and t.funding_bucket = 'free'
     and t.unlock_time < now() - interval '1 month'
     and not exists (select 1 from public.saved_memories s where s.capsule_id = t.id);
  get diagnostics v_deleted = row_count;
  return v_deleted;
end;
$$;

revoke all on function public.delete_expired_free_capsules(uuid[]) from public, anon, authenticated;
grant execute on function public.delete_expired_free_capsules(uuid[]) to service_role;
