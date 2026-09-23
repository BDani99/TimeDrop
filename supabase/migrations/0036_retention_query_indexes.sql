-- expired_free_capsules() (0024, 0031) filters time_capsules by
-- funding_bucket = 'free' and unlock_time, then anti-joins against
-- saved_memories.capsule_id. Neither predicate had a supporting index:
-- saved_memories only had a composite (user_id, capsule_id) unique index,
-- whose leading column isn't capsule_id, and time_capsules had no index
-- covering the free/unlock_time filter. Both become sequential scans as the
-- tables grow; the purge job runs on a schedule, so this is a quiet cost
-- rather than an outage, but cheap to fix now before volume makes it one.
create index if not exists saved_memories_capsule_id_idx
  on public.saved_memories (capsule_id);

create index if not exists time_capsules_free_unlock_idx
  on public.time_capsules (unlock_time)
  where funding_bucket = 'free';
