-- Auth hardening groundwork: an audit trail, single-use merge grants that
-- prove ownership of the anonymous account being merged away, and a record of
-- storage prefixes inherited through a merge.
--
-- Why merge grants exist
-- ----------------------
-- `merge-anonymous-account` runs with the service-role key and reassigns every
-- row owned by `anonymousUserId` to the caller. Verifying only the CALLER's JWT
-- proves the caller owns the *target* — it proves nothing about the *source*.
-- Without a source-ownership proof any authenticated user could pass a
-- stranger's anonymous uuid and steal, then delete, that stranger's account.
--
-- The client therefore calls `request_merge_grant()` while it is still the
-- anonymous user (the only moment it can prove it IS that user), stashes the
-- returned token, and hands it back after the OAuth round trip. Only the
-- token's SHA-256 is stored, so a database leak does not yield usable grants.
--
-- The grant is deliberately REQUIRED by the Edge Function — there is no
-- "accept a missing token for backward compatibility" branch, because such a
-- branch keeps the hole open indefinitely.

-- ── Audit trail ──────────────────────────────────────────────────────────────
create table public.audit_log (
  id         bigserial primary key,
  user_id    uuid,
  action     text not null,
  metadata   jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index audit_log_user_idx on public.audit_log (user_id, created_at desc);

alter table public.audit_log enable row level security;
-- Intentionally no policies: written and read only by the service role.
revoke all on table public.audit_log from anon, authenticated;

-- ── Merge grants ─────────────────────────────────────────────────────────────
create table public.merge_grants (
  id             uuid primary key default gen_random_uuid(),
  token_hash     text not null unique,
  source_user_id uuid not null references auth.users(id) on delete cascade,
  created_at     timestamptz not null default now(),
  expires_at     timestamptz not null,
  consumed_at    timestamptz
);

create index merge_grants_source_idx on public.merge_grants (source_user_id);

alter table public.merge_grants enable row level security;
-- Intentionally no policies: reachable only through the two functions below.
-- In particular the client must never be able to SELECT token_hash.
revoke all on table public.merge_grants from anon, authenticated;

-- Storage folders inherited from anonymous accounts merged into this user.
--
-- We deliberately do NOT move `capsule-media` objects during a merge: their
-- paths are embedded inside the AES-GCM encrypted capsule metadata, which the
-- server cannot decrypt or rewrite, so moving the files would break every
-- share link already handed out. Recording the old prefix instead keeps
-- account deletion able to find and purge those objects later.
create table public.user_storage_prefixes (
  user_id    uuid not null references auth.users(id) on delete cascade,
  prefix     text not null,
  created_at timestamptz not null default now(),
  primary key (user_id, prefix)
);

alter table public.user_storage_prefixes enable row level security;
-- Intentionally no policies: service role only.
revoke all on table public.user_storage_prefixes from anon, authenticated;

-- ── Functions ────────────────────────────────────────────────────────────────

-- Issues a single-use, 15-minute token proving the caller owns the account it
-- is called from. Returns the raw token; only its hash is persisted, so the
-- value cannot be recovered from the database afterwards.
--
-- Requesting a new grant invalidates any previous unconsumed one for the same
-- user, so an abandoned link attempt cannot leave a usable token lying around.
--
-- pgcrypto lives in the `extensions` schema on Supabase, so `digest` and
-- `gen_random_bytes` are schema-qualified rather than added to search_path —
-- a SECURITY DEFINER function should keep the narrowest path it can.
create or replace function public.request_merge_grant()
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_token text;
begin
  if v_uid is null then
    raise exception 'Not authenticated' using errcode = 'TD002';
  end if;

  v_token := encode(extensions.gen_random_bytes(32), 'hex');

  delete from public.merge_grants
   where source_user_id = v_uid
     and consumed_at is null;

  insert into public.merge_grants (token_hash, source_user_id, expires_at)
  values (
    encode(extensions.digest(v_token, 'sha256'), 'hex'),
    v_uid,
    now() + interval '15 minutes'
  );

  return v_token;
end;
$$;

revoke all on function public.request_merge_grant() from public, anon;
grant execute on function public.request_merge_grant() to authenticated;

-- Atomically validates and burns a grant. Returns true only when the token
-- matches, is unexpired, unconsumed, and was issued by `p_expected_source` —
-- the UPDATE ... WHERE ... RETURNING does all four checks and the burn in one
-- statement, so two concurrent calls cannot both succeed.
create or replace function public.consume_merge_grant(
  p_token           text,
  p_expected_source uuid
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  if p_token is null or p_expected_source is null then
    return false;
  end if;

  update public.merge_grants
     set consumed_at = now()
   where token_hash = encode(extensions.digest(p_token, 'sha256'), 'hex')
     and source_user_id = p_expected_source
     and consumed_at is null
     and expires_at > now()
  returning id into v_id;

  return v_id is not null;
end;
$$;

-- Service role only: the client must never be able to burn its own grant, and
-- `anon` inherits EXECUTE via PUBLIC unless PUBLIC itself is revoked.
revoke all on function public.consume_merge_grant(text, uuid) from public, anon, authenticated;
grant execute on function public.consume_merge_grant(text, uuid) to service_role;
