-- Store-reviewer access: ten taps on the paywall title, then a passcode.
--
-- WHY THE PASSCODE LIVES ON THE SERVER
-- ------------------------------------
-- The previous implementation compiled the passcode into the binary
-- (`Env.reviewerBypassPassword`), so anyone who unpacked the APK had it, it
-- could not be rotated or switched off without shipping a new build, and the
-- server had no idea a reviewer existed — which matters now that the drop
-- quota is enforced in the database.
--
-- Here the passcode never reaches the client: the app posts a candidate to a
-- SECURITY DEFINER function that compares it against a salted hash in a table
-- no client key can read.
--
-- WHY NO PASSCODE IS SEEDED HERE
-- ------------------------------
-- This migration deliberately arms nothing. It creates the salt and leaves the
-- kill switch OFF. Committing the passcode — even hashed, and especially in
-- plaintext — puts it in every clone of the repository forever. An operator
-- sets it once by hand, directly via the Supabase dashboard SQL editor or psql.
--
-- `reviewer_flags` itself is created in 0020, because create_pending_capsule()
-- must consult it to let a reviewer bypass the quota server-side.

-- ── Secrets no client may read ───────────────────────────────────────────────
create table public.secret_settings (
  setting_key   text primary key,
  setting_value jsonb not null,
  description   text,
  updated_at    timestamptz not null default now()
);

alter table public.secret_settings enable row level security;
-- RLS on with NO policies, plus an explicit revoke: unreadable and unwritable
-- through the anon or authenticated keys under any circumstances.
revoke all on table public.secret_settings from anon, authenticated;

-- ── Attempt log / rate limiting ──────────────────────────────────────────────
create table public.reviewer_passcode_attempts (
  id           bigserial primary key,
  user_id      uuid references auth.users(id) on delete cascade,
  succeeded    boolean not null,
  attempted_at timestamptz not null default now()
);

create index reviewer_passcode_attempts_user_idx
  on public.reviewer_passcode_attempts (user_id, attempted_at desc);

alter table public.reviewer_passcode_attempts enable row level security;
revoke all on table public.reviewer_passcode_attempts from anon, authenticated;

-- ── Validation ───────────────────────────────────────────────────────────────
-- Returns true only when the passcode matches, the feature is enabled, and the
-- caller is under the attempt limit. Every attempt is logged, including the
-- throttled ones, so a brute-force shows up in the table.
--
-- pgcrypto lives in the `extensions` schema on Supabase, hence the qualified
-- calls rather than widening this function's search_path.
create or replace function public.validate_reviewer_passcode(p_code text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid      uuid := auth.uid();
  v_enabled  boolean;
  v_salt     text;
  v_hash     text;
  v_attempts int;
  v_limit    int := 5;
  v_ok       boolean := false;
begin
  if v_uid is null or p_code is null or length(p_code) = 0 then
    return false;
  end if;

  -- Kill switch: flip this off once the app is approved, no rebuild needed.
  select coalesce((setting_value #>> '{}')::boolean, false)
    into v_enabled
    from public.secret_settings
   where setting_key = 'reviewer_passcode_enabled';

  if not coalesce(v_enabled, false) then
    insert into public.reviewer_passcode_attempts (user_id, succeeded) values (v_uid, false);
    return false;
  end if;

  select count(*) into v_attempts
    from public.reviewer_passcode_attempts
   where user_id = v_uid
     and attempted_at > now() - interval '24 hours';

  if v_attempts >= v_limit then
    insert into public.reviewer_passcode_attempts (user_id, succeeded) values (v_uid, false);
    return false;
  end if;

  select setting_value #>> '{}' into v_salt
    from public.secret_settings where setting_key = 'reviewer_passcode_salt';
  select setting_value #>> '{}' into v_hash
    from public.secret_settings where setting_key = 'reviewer_passcode_sha256';

  -- Not armed yet: no hash has been set by an operator.
  if v_hash is null or v_salt is null then
    insert into public.reviewer_passcode_attempts (user_id, succeeded) values (v_uid, false);
    return false;
  end if;

  v_ok := encode(extensions.digest(p_code || v_salt, 'sha256'), 'hex') = v_hash;

  insert into public.reviewer_passcode_attempts (user_id, succeeded) values (v_uid, v_ok);

  if v_ok then
    insert into public.reviewer_flags (user_id, is_reviewer, granted_at, revoked_at)
    values (v_uid, true, now(), null)
    on conflict (user_id) do update
      set is_reviewer = true, granted_at = now(), revoked_at = null;
  end if;

  return v_ok;
end;
$$;

revoke all on function public.validate_reviewer_passcode(text) from public, anon;
grant execute on function public.validate_reviewer_passcode(text) to authenticated;

-- ── Seed: disabled, with a per-deployment salt ───────────────────────────────
-- The salt is generated at migration time, so it differs per environment and
-- never appears in version control. No passcode hash is inserted.
insert into public.secret_settings (setting_key, setting_value, description)
values
  ('reviewer_passcode_enabled', 'false'::jsonb,
   'Kill switch. Turn on for a store submission, off once approved.'),
  ('reviewer_passcode_salt',
   to_jsonb(encode(extensions.gen_random_bytes(16), 'hex')),
   'Per-deployment salt for the reviewer passcode hash. Never commit.')
on conflict (setting_key) do nothing;
