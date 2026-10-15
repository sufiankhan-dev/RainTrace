# RLS hardening: owner-chain enforcement and private photo storage

## Goal

Review the existing schema/RLS and make sure a signed-in user can never read or
write another user's `properties`, `inspections`, `findings`, or photos — then
document exactly how that is verified and what still depends on authentication
shipping. No UI, no app wiring in this task.

## Inspected state

- `supabase/migrations/20261015135508_initial_schema.sql`: three tables with
  RLS enabled and one owner policy each (`created_by = auth.uid()` via
  `for all to authenticated … using … with check`). `anon` is revoked; grants
  to `authenticated`/`service_role` are select/insert/update/delete.
- Auth is NOT implemented: no sign-in UI, no `auth.users` creation path, and no
  app code queries these tables yet (grep for `supabase`/`from(` in `app/`,
  `lib/` returns only the client helpers). `lib/supabase/admin.ts` is the only
  privileged client and BYPASSES RLS.
- No storage bucket, no storage policies, no upload flow. `config.toml` enables
  storage locally but the storage/imgproxy containers are currently stopped
  (`supabase status`), which is irrelevant to SQL-level verification.
- Local probes: `postgres` is not superuser but has `rolbypassrls = t`, is a
  member of `authenticated`/`anon`/`service_role`, and can create policies on
  `storage.objects`; `storage.buckets.type` is a NOT NULL enum (insert needs
  `'STANDARD'`); `storage.objects.path_tokens` is generated; no default storage
  policies exist; `anonymous` sign-in is disabled in `config.toml`.
- Convention (bundled `supabase-postgres-best-practices` skill): wrap
  `auth.uid()` in a subquery in policies, index policy columns, keep RLS on by
  default.

## Problems found

1. **Foreign keys are not covered by RLS.** The current `with check` only tests
   `created_by = auth.uid()`. User B can insert a row that references user A's
   parent: `inspections.property_id` pointing at A's property, or
   `findings.inspection_id` pointing at A's inspection. Those rows are attributed
   to B (A's read policies hide them) but they still bloat A's chain and give a
   weak existence oracle — "not mine" and "does not exist" return different
   errors. Users can also set `created_by` to another user's id to plant rows in
   someone else's view (blocked today only because the policy compares it to
   `auth.uid()`, but the value is client-supplied).
2. **Ownership is client-supplied.** `created_by` has no default, so every
   insert must echo `auth.uid()` back; a null value is silently denied rather
   than owned.
3. **No photos are protected.** Findings store `photo_path`, but there is no
   bucket or storage policy, so nothing defines who may read/write those objects.

## Design decisions

- **Table policies become owner + parent-chain checks.** A row is visible and
  writable only when `created_by = auth.uid()` **and** the whole parent chain is
  owned by the caller (`inspections` → its property; `findings` → its inspection
  → its property). One `for all` policy per table, `to authenticated`, with
  matching `using` and `with check`, mirroring the existing style.
- **Server-derived ownership.** `alter column created_by set default
  auth.uid()` on all three tables. Authenticated inserts no longer have to send
  `created_by`; service_role/admin inserts (no JWT `sub`) still default to NULL,
  so the existing nullable, `on delete set null` behaviour and pre-auth rows are
  preserved.
- **Private `findings` bucket.** `id = 'findings'`, `public = false`,
  `file_size_limit = 50MiB`, `allowed_mime_types` limited to the image types the
  field flow needs (jpeg/png/webp/heic/heif), `type = 'STANDARD'`. Object names
  are `<inspection_id>/<uuid>.<ext>`; `photo_path` stores `findings/<name>`.
- **One owner policy on `storage.objects`.** Folder segment 1 must be an
  inspection the caller owns; `with check` additionally requires exactly one
  folder level and an image extension. Absence of any `anon` policy keeps the
  bucket invisible to anonymous requests. `service_role` keeps full access for
  signed-URL generation and cleanup.
- **Keep RLS enforcement on `postgres` off** (no `force row level security`):
  the local `postgres` role has BYPASSRLS and migrations/seeds rely on it;
  PostgREST always switches to `anon`/`authenticated`, so forced RLS would only
  break future seeds without changing API behaviour.
- **Verification is a script, not prose.** `supabase/tests/rls_verification.sql`
  seeds two throwaway users, then exercises every deny/allow case as `anon`,
  user A, user B, and `service_role`, raising an exception (non-zero exit) on
  any mismatch. It is plain SQL with `DO` blocks so it runs via `psql` or the
  SQL editor, not only under pgTAP.

## Files to change

- `supabase/migrations/20261015180000_rls_owner_chain_and_storage.sql` (new)
- `supabase/tests/rls_verification.sql` (new)
- `prompts/rls-hardening.md` (this plan file)
- `README.md` (RLS semantics, honest auth-status note, verification steps)

## Security considerations

- RLS + storage RLS are the access-control boundary, not the UI.
- `service_role` bypasses RLS by design; it stays server-only
  (`lib/supabase/admin.ts`, guarded by `server-only`).
- Storage stays private; reports/photos are shared via short-lived signed URLs
  created server-side, never a public bucket URL.
- LIMITATIONS TO STATE HONESTLY: authentication is not implemented, so no
  request currently arrives as `authenticated` — the app has no per-user
  isolation in practice yet, and any app-side DB access must be treated as
  privileged. MIME enforcement by the storage service checks the client-declared
  `content_type`, and the RLS extension check trusts the object name; real
  content sniffing is not implemented. Deriving coordinates from EXIF is out of
  scope. No secrets in migrations or docs.

## Acceptance criteria

- Migration applies cleanly on a fresh local database (`supabase db reset`).
- `anon` cannot read or write any of the three tables or `storage.objects`.
- User A sees only their own properties/inspections/findings/photos; user B
  sees, updates, and deletes none of A's rows and cannot insert rows under A's
  property/inspection (denied by policy, not by UI).
- A row inserted through `authenticated` with no `created_by` is owned by the
  caller (server default).
- Photos are only readable/writable under an inspection the caller owns; other
  buckets, single-level names, and non-image extensions are rejected.
- `service_role` still sees all rows (admin path intact).
- `supabase db advisors` reports no new lint for these objects.
- `npm run lint` and `npx tsc --noEmit` still pass (no TS changes expected).

## Checks and manual test steps

1. `supabase db reset` — applies both migrations.
2. `Get-Content supabase/tests/rls_verification.sql -Raw | docker exec -i
   supabase_db_raintrace psql -U postgres -d postgres -v ON_ERROR_STOP=1` —
   expect `NOTICE: RLS verification passed` and exit code 0.
3. Temporarily weaken a policy and confirm the script fails (e.g. drop the
   `with check` on `inspections`), then restore via `supabase db reset`.
4. `supabase db advisors` — no findings for the new objects.
5. `npm run lint` and `npx tsc --noEmit`.
