-- Memory timeline timestamps for Vault detail view.
alter table public.received_capsules
  add column if not exists capsule_created_at timestamptz,
  add column if not exists unlocked_at timestamptz,
  add column if not exists viewed_at timestamptz;
