-- Backs "Keep this memory forever" (MemorySavedModal) + the Vault's
-- received/saved list.
--
-- Deliberate, narrow, consent-gated relaxation of the Zero-Knowledge
-- principle: storing the raw AES key server-side lets a saved memory survive
-- a phone change via Apple/Google account linking (Sprint 3), since there is
-- no passphrase step in the spec to derive a key-wrapping secret from. This
-- ONLY applies to capsules a user explicitly opts into saving here — it does
-- not touch the primary time_capsules flow, which stays zero-knowledge.
--
-- Hardening note (not built for MVP): encrypt encryption_key at rest via
-- pgsodium/Supabase Vault column encryption so a raw DB dump doesn't expose
-- keys in plaintext even though RLS restricts row access.
create table public.saved_memories (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references auth.users(id) on delete cascade,
  capsule_id     uuid not null references public.time_capsules(id) on delete cascade,
  encryption_key text not null,
  saved_at       timestamptz not null default now(),
  unique (user_id, capsule_id)
);

alter table public.saved_memories enable row level security;

create policy "saved_memories_select_own"
  on public.saved_memories for select using (user_id = auth.uid());
create policy "saved_memories_insert_own"
  on public.saved_memories for insert with check (user_id = auth.uid());
create policy "saved_memories_delete_own"
  on public.saved_memories for delete using (user_id = auth.uid());
