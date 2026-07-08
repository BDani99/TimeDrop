insert into storage.buckets (id, name, public)
values ('capsule-media', 'capsule-media', false);

-- Upload path convention (enforced by policy): "{auth.uid()}/{uuid}.enc"
create policy "capsule_media_insert_own_folder"
on storage.objects for insert
with check (
  bucket_id = 'capsule-media'
  and auth.role() = 'authenticated'
  and (storage.foldername(name))[1] = auth.uid()::text
);

-- Any authenticated (incl. anonymous) user may READ any object in this
-- bucket. This mirrors the RPC's trust model: the object body is itself an
-- opaque AES-GCM envelope (see mobile crypto design), the object path is an
-- unguessable UUID never exposed except inside the encrypted metadata
-- payload, and content-type is stored as application/octet-stream (the real
-- mime type lives only inside the encrypted JSON) — so a permissive read
-- policy does not leak plaintext. This relaxation is required because the
-- *recipient* (a different auth.uid() than the creator) must be able to
-- download the file.
create policy "capsule_media_select_authenticated"
on storage.objects for select
using (
  bucket_id = 'capsule-media'
  and auth.role() = 'authenticated'
);

create policy "capsule_media_update_own_folder"
on storage.objects for update
using (
  bucket_id = 'capsule-media'
  and (storage.foldername(name))[1] = auth.uid()::text
);

create policy "capsule_media_delete_own_folder"
on storage.objects for delete
using (
  bucket_id = 'capsule-media'
  and (storage.foldername(name))[1] = auth.uid()::text
);
