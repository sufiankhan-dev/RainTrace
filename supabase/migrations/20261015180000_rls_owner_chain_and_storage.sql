-- RainTrace RLS hardening: owner-chain checks + private photo storage.
--
-- Why this migration exists
-- -------------------------
-- The initial schema (20261015135508) enabled RLS with one owner policy per
-- table: `created_by = auth.uid()`. That blocks cross-user reads, but a
-- foreign key is not protected by RLS. A signed-in user could still INSERT a
-- row that references someone else's parent — an inspection whose `property_id`
-- points at another user's property, or a finding under another user's
-- inspection — as long as they set `created_by` to themselves. Those rows
-- pollute another user's chain and leak a weak existence oracle (a policy
-- denial and a foreign-key violation are distinguishable). `created_by` itself
-- was also client-supplied.
--
-- This migration:
--   1. Defaults `created_by` to `auth.uid()` so ownership is derived
--      server-side instead of being trusted from the request. The column stays
--      nullable, so service_role/admin inserts and legacy pre-auth rows keep
--      working (`on delete set null` unchanged).
--   2. Replaces the three table policies with owner + parent-chain checks: a
--      row is only visible/writable when the caller owns the row AND the whole
--      chain (property -> inspection -> finding).
--   3. Adds a private `findings` storage bucket and owner-scoped storage
--      policies so photos cannot be listed, read, or written across users.
--
-- Authentication is not implemented in the app yet (see README). These policies
-- take effect the moment requests arrive as the `authenticated` role. Until
-- then app access must go through the server-only service-role client, which
-- BYPASSES RLS — so this migration hardens the schema, it does not by itself
-- make the running app tenant-isolated.

-- ---------------------------------------------------------------------------
-- 1. Server-derived ownership
-- ---------------------------------------------------------------------------
-- auth.uid() resolves to the JWT `sub` claim, or NULL when there is no JWT
-- (service_role/admin work). Authenticated inserts may omit created_by.

alter table public.properties alter column created_by set default auth.uid();
alter table public.inspections alter column created_by set default auth.uid();
alter table public.findings alter column created_by set default auth.uid();

comment on column public.properties.created_by is
  'auth.users id of the creator. Defaults to auth.uid(); NULL for service_role/admin or legacy pre-auth rows.';
comment on column public.inspections.created_by is
  'auth.users id of the creator. Defaults to auth.uid(); NULL for service_role/admin or legacy pre-auth rows.';
comment on column public.findings.created_by is
  'auth.users id of the creator. Defaults to auth.uid(); NULL for service_role/admin or legacy pre-auth rows.';

-- ---------------------------------------------------------------------------
-- 2. Owner + parent-chain policies
-- ---------------------------------------------------------------------------
-- `for all` covers select/insert/update/delete. USING filters existing rows;
-- WITH CHECK validates new/updated rows. auth.uid() is wrapped in a subquery so
-- it is evaluated once per query rather than once per row. The parent EXISTS
-- checks also run under RLS, so they can only ever match parents the caller
-- owns; the explicit `created_by = auth.uid()` predicates keep the intent
-- readable and independent of parent-table policy changes.

drop policy if exists properties_owner_all on public.properties;
drop policy if exists inspections_owner_all on public.inspections;
drop policy if exists findings_owner_all on public.findings;

create policy properties_owner_all on public.properties
  for all
  to authenticated
  using (created_by = (select auth.uid()))
  with check (created_by = (select auth.uid()));

create policy inspections_owner_all on public.inspections
  for all
  to authenticated
  using (
    created_by = (select auth.uid())
    and exists (
      select 1
      from public.properties p
      where p.id = inspections.property_id
        and p.created_by = (select auth.uid())
    )
  )
  with check (
    created_by = (select auth.uid())
    and exists (
      select 1
      from public.properties p
      where p.id = inspections.property_id
        and p.created_by = (select auth.uid())
    )
  );

create policy findings_owner_all on public.findings
  for all
  to authenticated
  using (
    created_by = (select auth.uid())
    and exists (
      select 1
      from public.inspections i
      join public.properties p on p.id = i.property_id
      where i.id = findings.inspection_id
        and i.created_by = (select auth.uid())
        and p.created_by = (select auth.uid())
    )
  )
  with check (
    created_by = (select auth.uid())
    and exists (
      select 1
      from public.inspections i
      join public.properties p on p.id = i.property_id
      where i.id = findings.inspection_id
        and i.created_by = (select auth.uid())
        and p.created_by = (select auth.uid())
    )
  );

comment on policy properties_owner_all on public.properties is
  'A user may only see and change properties they created (created_by = auth.uid()).';
comment on policy inspections_owner_all on public.inspections is
  'A user may only see and change inspections they created on properties they own.';
comment on policy findings_owner_all on public.findings is
  'A user may only see and change findings they created on inspections they own under properties they own.';

-- ---------------------------------------------------------------------------
-- 3. Private photo storage
-- ---------------------------------------------------------------------------
-- One private bucket. Object names are `<inspection_id>/<uuid>.<ext>`; the
-- finding stores `photo_path` as `findings/<object name>`. allowed_mime_types
-- and file_size_limit are enforced by the storage service on upload.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types, type)
values (
  'findings',
  'findings',
  false,
  52428800,
  array['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif'],
  'STANDARD'
)
on conflict (id) do update
  set public = excluded.public,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- One policy for the whole bucket. USING gates select/update/delete on owning
-- the inspection named by the first path segment; WITH CHECK additionally
-- requires exactly one folder level and an image file extension for writes.
-- There is deliberately no anon policy: without one, anonymous requests get
-- nothing. service_role bypasses RLS for signed-URL creation and cleanup.

drop policy if exists inspection_photos_owner_all on storage.objects;

create policy inspection_photos_owner_all on storage.objects
  for all
  to authenticated
  using (
    bucket_id = 'findings'
    and (storage.foldername(name))[1] is not null
    and exists (
      select 1
      from public.inspections i
      where i.id::text = lower((storage.foldername(name))[1])
        and i.created_by = (select auth.uid())
    )
  )
  with check (
    bucket_id = 'findings'
    and (storage.foldername(name))[1] is not null
    and (storage.foldername(name))[2] is null
    and name ~* '\.(jpe?g|png|webp|heic|heif)$'
    and exists (
      select 1
      from public.inspections i
      where i.id::text = lower((storage.foldername(name))[1])
        and i.created_by = (select auth.uid())
    )
  );

-- No `comment on policy` here: `storage.objects` is owned by
-- supabase_storage_admin, and COMMENT ON POLICY requires strict table
-- ownership, which the migration role does not have.
