-- Rate-limits share-code guessing.
--
-- THE PROBLEM
-- -----------
-- `get_capsule_by_share_id` had no limit of any kind. The anon key ships inside
-- the app and an anonymous session costs one request, so anyone could try
-- 6-character codes as fast as the API answers. Every hit returns the drop's
-- exact latitude and longitude.
--
-- The *content* stays safe — the decryption key lives in the link's `#`
-- fragment and never reaches the server — but the coordinates alone are
-- sensitive: they are a real place a real person chose. Today the hit rate is
-- tiny because there are few capsules; it grows linearly with the app.
--
-- WHY ONLY MISSES ARE COUNTED
-- ---------------------------
-- The Radar screen polls this function every 3 seconds while a capsule is
-- still uploading (see `_ensurePendingPoll` in radar_screen.dart) — over a
-- thousand calls an hour for one legitimate viewing. A limit on total calls
-- would break the app on day one.
--
-- A legitimate caller almost always HITS: they were handed a real link. A
-- guesser almost always MISSES. Counting only misses therefore costs real users
-- nothing (a few mistyped codes are still fine) while making enumeration
-- useless.
--
-- HONEST LIMITATION
-- -----------------
-- Sign-up is open, so a determined attacker can rotate anonymous accounts to
-- reset their own counter. This raises the cost — a signup round trip per 20
-- guesses, on top of Supabase's own per-IP auth limits — but does not make
-- enumeration impossible. It is a speed bump on a low-yield attack, not a
-- proof. Anything stronger would need per-IP limiting at the edge.

create table public.share_lookup_misses (
  id           bigserial primary key,
  user_id      uuid not null references auth.users(id) on delete cascade,
  share_id     text not null,
  attempted_at timestamptz not null default now()
);

create index share_lookup_misses_user_idx
  on public.share_lookup_misses (user_id, attempted_at desc);

alter table public.share_lookup_misses enable row level security;
-- No policies: only the SECURITY DEFINER function below writes here, and no
-- client has any reason to read it.
revoke all on table public.share_lookup_misses from anon, authenticated;

-- Tunable without a release. 20 wrong guesses an hour is far more than a
-- fat-fingered user needs and far less than a guesser wants.
insert into public.system_settings (key, value)
values ('share_lookup_miss_hourly_limit', 20)
on conflict (key) do nothing;

-- Return shape is unchanged from 0012 — only the guard and the miss log are
-- new. Note this is no longer STABLE: it writes the miss log.
drop function if exists public.get_capsule_by_share_id(text);

create or replace function public.get_capsule_by_share_id(p_share_id text)
returns table (
  id                uuid,
  share_id          text,
  latitude          float8,
  longitude         float8,
  unlock_time       timestamptz,
  created_at        timestamptz,
  status            text,
  encrypted_payload text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_limit  int;
  v_misses int;
  v_found  boolean;
begin
  if v_uid is null then
    raise exception 'Not authenticated' using errcode = 'TD002';
  end if;

  select coalesce(
           (select s.value::int from public.system_settings s
             where s.key = 'share_lookup_miss_hourly_limit'),
           20)
    into v_limit;

  select count(*) into v_misses
    from public.share_lookup_misses m
   where m.user_id = v_uid
     and m.attempted_at > now() - interval '1 hour';

  if v_misses >= v_limit then
    raise exception 'Too many failed lookups. Try again later.'
      using errcode = 'TD005';
  end if;

  select exists(
    select 1 from public.time_capsules tc where tc.share_id = p_share_id
  ) into v_found;

  if not v_found then
    insert into public.share_lookup_misses (user_id, share_id)
    values (v_uid, p_share_id);

    -- Opportunistic tidy-up so the log cannot grow without bound. Only ever
    -- touches this caller's own rows, and only ones already past the window.
    delete from public.share_lookup_misses
     where user_id = v_uid
       and attempted_at < now() - interval '24 hours';
  end if;

  return query
    select
      tc.id,
      tc.share_id,
      tc.latitude,
      tc.longitude,
      tc.unlock_time,
      tc.created_at,
      tc.status,
      -- Withheld until unlock time even though it is only ciphertext: keeps
      -- storage egress aligned with the countdown UX.
      case when now() >= tc.unlock_time then tc.encrypted_payload else null end
    from public.time_capsules tc
   where tc.share_id = p_share_id
   limit 1;
end;
$$;

-- `anon` inherits EXECUTE through PUBLIC, so PUBLIC must be revoked too — not
-- just anon. Every real caller holds an authenticated JWT (the app signs in
-- anonymously at startup), so unauthenticated scraping stays closed off.
revoke all on function public.get_capsule_by_share_id(text) from public, anon;
grant execute on function public.get_capsule_by_share_id(text) to authenticated;

-- Corrects the estimate in 0003: the share alphabet is 32 characters
-- (AppConstants.shareIdAlphabet, Crockford base32), not 36, so the keyspace is
-- 32^6 ≈ 1.07e9 — half what the original comment claimed. Worth being exact
-- about, since that number is the whole argument for share-code secrecy.
comment on function public.get_capsule_by_share_id(text) is
  'Public-by-share-code capsule lookup. Keyspace is 32^6 (~1.07e9). Rate '
  'limited on misses only, because the Radar polls this on a 3s timer.';
