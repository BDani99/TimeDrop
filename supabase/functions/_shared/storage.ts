import type { SupabaseClient } from 'jsr:@supabase/supabase-js@2';

/// Supabase Storage caps `list()` at 1000 entries per call. Callers that pass a
/// bare `{ limit: 1000 }` silently drop everything past the first page — which
/// is how deletion paths end up leaving orphaned objects behind for exactly the
/// heaviest accounts. Everything here pages properly.
const PAGE_SIZE = 1000;

/// Every object path directly under `prefix`, following pagination to the end.
export async function listAllPrefix(
  admin: SupabaseClient,
  bucket: string,
  prefix: string,
): Promise<string[]> {
  const paths: string[] = [];
  let offset = 0;

  for (;;) {
    const { data, error } = await admin.storage
      .from(bucket)
      .list(prefix, { limit: PAGE_SIZE, offset });

    if (error) throw error;
    if (!data || data.length === 0) break;

    for (const entry of data) {
      // Entries without an id are folders; this bucket is flat per user, but
      // guard anyway so a nested layout doesn't produce bogus paths.
      if (entry.id === null) continue;
      paths.push(`${prefix}/${entry.name}`);
    }

    if (data.length < PAGE_SIZE) break;
    offset += data.length;
  }

  return paths;
}

/// Deletes every object under `prefix`. Returns how many were removed, and
/// pushes a human-readable note onto `warnings` for any failure instead of
/// throwing — deletion is best-effort per prefix, and the caller decides
/// whether partial failure is fatal.
export async function purgeBucketPrefix(
  admin: SupabaseClient,
  bucket: string,
  prefix: string,
  warnings: string[],
): Promise<number> {
  let paths: string[];
  try {
    paths = await listAllPrefix(admin, bucket, prefix);
  } catch (error) {
    warnings.push(`list ${bucket}/${prefix}: ${String(error)}`);
    return 0;
  }

  if (paths.length === 0) return 0;

  let removed = 0;
  // `remove()` also has a per-call ceiling, so delete in the same page size.
  for (let i = 0; i < paths.length; i += PAGE_SIZE) {
    const batch = paths.slice(i, i + PAGE_SIZE);
    const { error } = await admin.storage.from(bucket).remove(batch);
    if (error) {
      warnings.push(`remove ${bucket}/${prefix} batch ${i}: ${error.message}`);
      continue;
    }
    removed += batch.length;
  }

  return removed;
}
