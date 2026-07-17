-- Feedback table: stores in-app bug reports and general feedback.
-- Each row is owned by the user who submitted it (auth.uid()).
-- Admins read via the service role; the app only inserts.

create table if not exists public.feedback (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid references auth.users(id) on delete set null,
  type        text not null check (type in ('bug', 'feedback', 'other')),
  message     text not null check (char_length(message) between 1 and 2000),
  app_version text,
  platform    text,
  created_at  timestamptz not null default now()
);

-- Index for admin queries: newest first, filterable by type.
create index if not exists feedback_created_at_idx on public.feedback (created_at desc);
create index if not exists feedback_type_idx       on public.feedback (type);
create index if not exists feedback_user_id_idx    on public.feedback (user_id);

-- RLS: users can only insert their own rows; nobody can read via the anon key.
alter table public.feedback enable row level security;

create policy "Users can submit feedback"
  on public.feedback for insert
  to authenticated
  with check (user_id = auth.uid());

-- Anon users (anonymous sign-ins) are also 'authenticated' in Supabase.
-- The policy above already covers them since auth.uid() returns their uid.
