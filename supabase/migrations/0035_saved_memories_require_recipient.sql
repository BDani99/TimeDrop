-- saved_memories_insert_own (0005) only checked that the inserting row's
-- user_id matched the caller — it never checked that the caller actually
-- RECEIVED the capsule. A capsule's own creator could insert a saved_memories
-- row for their own free-tier capsule at zero cost, which the retention
-- purge (expired_free_capsules / delete_expired_free_capsules, 0024 + 0031)
-- treats as "kept" and permanently exempts from the free-tier purge —
-- defeating the storage-cost-control rationale those migrations exist for.
--
-- A saved memory only makes sense for something the user received, so
-- require a matching received_capsules row (which is only ever created via
-- the client's post-lookup flow, i.e. actually resolving the capsule as a
-- recipient) before allowing the insert.
drop policy "saved_memories_insert_own" on public.saved_memories;

create policy "saved_memories_insert_own"
  on public.saved_memories for insert
  with check (
    user_id = auth.uid()
    and exists (
      select 1 from public.received_capsules rc
      where rc.user_id = auth.uid()
        and rc.capsule_id = saved_memories.capsule_id
    )
  );
