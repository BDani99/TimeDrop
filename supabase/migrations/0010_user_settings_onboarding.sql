-- Per-account onboarding state: whether the intro questions + paywall flow
-- has been completed, plus the (optional) collected answers for later
-- personalization. Account-based (re-onboards on a fresh reinstall / new
-- anonymous account), which matches standard mobile onboarding behavior.
alter table public.user_settings
  add column if not exists onboarding_completed boolean not null default false,
  add column if not exists onboarding_answers jsonb;
