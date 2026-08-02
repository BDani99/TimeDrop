-- 0029 — the keepsake card
--
-- After a memory is opened in the field, the recipient gets a card: the
-- cracked capsule with the facts of the moment underneath it (where, when,
-- how long ago, how close they were standing). That card is not a one-off
-- animation — it stays with the drop, reachable by swiping past the video and
-- the photos, for as long as they keep the memory.
--
-- Everything on it is already stored except one thing: how far away they were
-- when it opened. That number only exists for the seconds the radar is alive,
-- so it has to be written down at the moment of unlock or it is gone.

alter table public.received_capsules
  add column if not exists unlock_distance_meters double precision;

comment on column public.received_capsules.unlock_distance_meters is
  'How far the recipient was standing from the drop when it unlocked, in '
  'metres. Recorded once, at first view, so the keepsake card can be redrawn '
  'identically on every later replay. Null for capsules opened before this '
  'column existed, and for any replay-only row.';
