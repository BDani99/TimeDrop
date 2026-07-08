create table public.user_settings (
  user_id         uuid primary key references auth.users(id) on delete cascade,
  free_drop_used  boolean not null default false,
  fcm_token       text
);

alter table public.user_settings enable row level security;

create policy "user_settings_select_own"
  on public.user_settings for select
  using (user_id = auth.uid());

create policy "user_settings_insert_own"
  on public.user_settings for insert
  with check (user_id = auth.uid());

create policy "user_settings_update_own"
  on public.user_settings for update
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- Auto-provision a settings row the moment any user (incl. anonymous) is
-- created, so client code never has to special-case "row doesn't exist yet."
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.user_settings (user_id) values (new.id)
  on conflict (user_id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
