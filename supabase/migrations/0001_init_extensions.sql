-- gen_random_uuid() ships enabled by default on Supabase, but make it explicit/idempotent.
create extension if not exists pgcrypto;
