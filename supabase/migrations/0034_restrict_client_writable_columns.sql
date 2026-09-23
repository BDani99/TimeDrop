-- Security hardening: the direct-table UPDATE policies on time_capsules and
-- received_capsules (0012, 0007) allow the owning client to write ANY column,
-- not just the ones the app actually needs to touch itself. Everything else
-- (unlock_time, latitude, longitude, city, funding_bucket, code_unlock_key on
-- time_capsules) is meant to be reachable only through the SECURITY DEFINER
-- RPCs (create_pending_capsule, update_sent_capsule_meta, ...), which run as
-- the function owner and are therefore unaffected by these column grants.
--
-- Two concrete problems this closes:
--
-- 1. A client could PATCH time_capsules directly and set media_paths to an
--    ARBITRARY path string (there is no ownership check on that column
--    today). purge-expired-capsules runs with the service-role key and blindly
--    deletes whatever media_paths lists, via the admin.storage.remove() call
--    in supabase/functions/purge-expired-capsules/index.ts. A caller who sets
--    their own free capsule's media_paths to point at another user's storage
--    object, then lets it expire, gets that other user's real media deleted —
--    a confused-deputy attack via the purge job. Fixed by the ownership
--    check in the trigger below.
--
-- 2. A client could PATCH time_capsules directly and change unlock_time /
--    latitude / longitude on an ALREADY-UNLOCKED capsule the recipient may be
--    actively navigating to in Radar, exactly the griefing scenario 0033's
--    RPC-side lock was written to close — except the RPC was never the only
--    path to those columns. Fixed by revoking column-level UPDATE for
--    everything outside the app's actual direct-write surface.
--
-- received_capsules gets the same treatment for the same reason, one notch
-- lower severity: without it, a recipient can directly rewrite the cached
-- unlock_time/latitude/longitude/share_id shown on their own keepsake card.
-- That can't affect another user's data or grant early access to real
-- content (unlock gating lives on time_capsules, read via the RPC), but
-- there's no reason to leave those columns client-writable either.

-- ── time_capsules ─────────────────────────────────────────────────────────
-- The Flutter client's only direct table write is
-- SupabaseService.updateCapsulePayload(), which sets exactly these three
-- columns while finalizing/retrying a background upload.
revoke update on public.time_capsules from authenticated;
grant update (encrypted_payload, media_paths, status) on public.time_capsules to authenticated;

create or replace function public.time_capsules_validate_update()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.media_paths is distinct from old.media_paths and new.media_paths is not null then
    if exists (
      select 1 from unnest(new.media_paths) as p
      where (storage.foldername(p))[1] is distinct from auth.uid()::text
    ) then
      raise exception 'media_paths must stay under the caller''s own storage prefix';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists time_capsules_validate_update on public.time_capsules;
create trigger time_capsules_validate_update
  before update on public.time_capsules
  for each row execute function public.time_capsules_validate_update();

-- ── received_capsules ────────────────────────────────────────────────────
-- The client's direct table writes only ever touch these five columns
-- (SupabaseService.updateReceivedCapsuleCity / markCapsuleUnlocked /
-- markReceivedCapsuleViewed).
revoke update on public.received_capsules from authenticated;
grant update (city, unlocked_at, is_viewed, viewed_at, unlock_distance_meters)
  on public.received_capsules to authenticated;
