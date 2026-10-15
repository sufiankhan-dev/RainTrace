-- RainTrace RLS verification
-- ==========================
-- Proves, at the database level, that a signed-in user cannot read or write
-- another user's properties, inspections, findings, or photos.
--
-- It runs entirely as the local `postgres` role (which is a member of
-- `authenticated`/`anon`/`service_role` and has BYPASSRLS), switches into each
-- role with `set role` + `set request.jwt.claims`, and raises an exception — so
-- psql exits non-zero — on any mismatch. It is re-runnable: it cleans up its own
-- fixed-id fixtures first.
--
-- Run (PowerShell, from the repo root):
--   Get-Content supabase/tests/rls_verification.sql -Raw |
--     docker exec -i supabase_db_raintrace psql -U postgres -d postgres `
--       -v ON_ERROR_STOP=1
--
-- Expected final line: NOTICE: RLS verification passed
--
-- The script assumes both migrations are applied (supabase db reset).

\set ON_ERROR_STOP on

-- The storage API sets this GUC on its own connection before deleting; the
-- statement-level `storage.protect_objects_delete` trigger raises unless it is
-- set. It only disables that guard — RLS remains the access boundary, so setting
-- it here does not let a user touch rows they cannot see.
set storage.allow_delete_query = 'true';

-- ---------------------------------------------------------------------------
-- Fixtures (fixed ids so cleanup and assertions are deterministic)
-- ---------------------------------------------------------------------------
-- users
--   A  11111111-1111-4111-8111-111111111111
--   B  22222222-2222-4222-8222-222222222222
-- properties
--   prop_a  00000000-0000-4000-a000-0000000000a1  (A, explicit created_by)
--   prop_ad 00000000-0000-4000-a000-0000000000a4  (A, default created_by)
--   prop_b  00000000-0000-4000-b000-0000000000b1  (B)
-- inspections
--   insp_a  00000000-0000-4000-a000-0000000000a2  (A, under prop_a)
--   insp_b  00000000-0000-4000-b000-0000000000b2  (B, under prop_b)
-- findings
--   find_a  00000000-0000-4000-a000-0000000000a3  (A, under insp_a)
--   find_b  00000000-0000-4000-b000-0000000000b3  (B, under insp_b)
-- storage objects
--   A  findings/<insp_a>/photo-a.jpg
--   B  findings/<insp_b>/photo-b.jpg

-- ---------------------------------------------------------------------------
-- 0. Cleanup any fixture from a previous run (current role: postgres)
-- ---------------------------------------------------------------------------

delete from storage.objects
where bucket_id = 'findings'
  and name in (
    '00000000-0000-4000-a000-0000000000a2/photo-a.jpg',
    '00000000-0000-4000-b000-0000000000b2/photo-b.jpg'
  );

delete from public.properties
where id in (
  '00000000-0000-4000-a000-0000000000a1',
  '00000000-0000-4000-a000-0000000000a4',
  '00000000-0000-4000-b000-0000000000b1'
)
or created_by in (
  '11111111-1111-4111-8111-111111111111',
  '22222222-2222-4222-8222-222222222222'
);

delete from auth.users
where id in (
  '11111111-1111-4111-8111-111111111111',
  '22222222-2222-4222-8222-222222222222'
);

insert into auth.users (id, email) values
  ('11111111-1111-4111-8111-111111111111', 'rls-verify-a@example.test'),
  ('22222222-2222-4222-8222-222222222222', 'rls-verify-b@example.test');

-- ---------------------------------------------------------------------------
-- 1. Anonymous role: no access at all
-- ---------------------------------------------------------------------------

set role anon;

do $verify$
declare
  n int;
  failing_insert text;
begin
  -- Reads: either permission denied (revoked) or zero rows (RLS). Never rows.
  foreach failing_insert in array array[
    'public.properties', 'public.inspections', 'public.findings', 'storage.objects'
  ]
  loop
    begin
      execute format('select count(*) from %s', failing_insert) into n;
      if n <> 0 then
        raise exception 'FAIL: anon saw % rows in %', n, failing_insert;
      end if;
    exception
      when insufficient_privilege then null; -- revoked: also acceptable
    end;
  end loop;

  -- Writes: must be denied outright.
  begin
    execute $q$insert into public.properties (name) values ('anon property')$q$;
    raise exception 'FAIL: anon inserted a property';
  exception when insufficient_privilege then null;
  end;

  begin
    execute $q$insert into storage.objects (bucket_id, name)
              values ('findings', '00000000-0000-4000-a000-0000000000a2/anon.jpg')$q$;
    raise exception 'FAIL: anon inserted a storage object';
  exception when insufficient_privilege then null;
  end;
end
$verify$;

reset role;

-- ---------------------------------------------------------------------------
-- 2. User A: owns its own chain, cannot be told to own someone else's rows
-- ---------------------------------------------------------------------------

set role authenticated;
set request.jwt.claims = '{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated"}';

insert into public.properties (id, name, created_by)
values ('00000000-0000-4000-a000-0000000000a1', 'RLS verify A', '11111111-1111-4111-8111-111111111111');

-- No created_by supplied: must default to auth.uid() server-side.
insert into public.properties (id, name)
values ('00000000-0000-4000-a000-0000000000a4', 'RLS verify A default');

insert into public.inspections (id, property_id, title)
values ('00000000-0000-4000-a000-0000000000a2', '00000000-0000-4000-a000-0000000000a1', 'A inspection');

insert into public.findings (id, inspection_id, photo_path, location_description)
values (
  '00000000-0000-4000-a000-0000000000a3',
  '00000000-0000-4000-a000-0000000000a2',
  'findings/00000000-0000-4000-a000-0000000000a2/photo-a.jpg',
  'A walkway drain'
);

do $verify$
declare
  n int;
  owner uuid;
begin
  -- Default ownership worked.
  select created_by into owner from public.properties
  where id = '00000000-0000-4000-a000-0000000000a4';
  if owner <> '11111111-1111-4111-8111-111111111111' then
    raise exception 'FAIL: created_by default was %, expected user A', owner;
  end if;

  -- Sees exactly its own rows so far.
  execute 'select count(*) from public.properties' into n;
  if n <> 2 then raise exception 'FAIL: user A sees % properties, expected 2', n; end if;
  execute 'select count(*) from public.inspections' into n;
  if n <> 1 then raise exception 'FAIL: user A sees % inspections, expected 1', n; end if;
  execute 'select count(*) from public.findings' into n;
  if n <> 1 then raise exception 'FAIL: user A sees % findings, expected 1', n; end if;

  -- Cannot plant a property owned by user B.
  begin
    execute $q$insert into public.properties (name, created_by)
              values ('A forgery', '22222222-2222-4222-8222-222222222222')$q$;
    raise exception 'FAIL: A inserted a property owned by B';
  exception when insufficient_privilege then null;
  end;

  -- Cannot add an inspection to a property it does not own (B's not created yet,
  -- so use a random unknown id: denial must win over the FK violation).
  begin
    execute $q$insert into public.inspections (property_id, title)
              values ('00000000-0000-4000-b000-0000000000b1', 'A on foreign property')$q$;
    raise exception 'FAIL: A inserted an inspection on a foreign property';
  exception when insufficient_privilege then null;
  end;
end
$verify$;

-- User A uploads a photo under its own inspection.
insert into storage.objects (bucket_id, name)
values ('findings', '00000000-0000-4000-a000-0000000000a2/photo-a.jpg');

do $verify$
declare
  n int;
begin
  -- Object-name rules: one folder level, image extension, owned inspection.
  begin
    execute $q$insert into storage.objects (bucket_id, name)
              values ('findings', '00000000-0000-4000-b000-0000000000b2/photo-a.png')$q$;
    raise exception 'FAIL: A wrote a photo into a foreign inspection folder';
  exception when insufficient_privilege then null;
  end;

  begin
    execute $q$insert into storage.objects (bucket_id, name)
              values ('findings', '00000000-0000-4000-a000-0000000000a2/nested/photo.png')$q$;
    raise exception 'FAIL: A wrote a photo with a nested path';
  exception when insufficient_privilege then null;
  end;

  begin
    execute $q$insert into storage.objects (bucket_id, name)
              values ('findings', '00000000-0000-4000-a000-0000000000a2/photo.txt')$q$;
    raise exception 'FAIL: A wrote a non-image object name';
  exception when insufficient_privilege then null;
  end;

  begin
    execute $q$insert into storage.objects (bucket_id, name)
              values ('findings', 'photo-a.jpg')$q$;
    raise exception 'FAIL: A wrote a root-level (no inspection folder) object';
  exception when insufficient_privilege then null;
  end;

  begin
    execute $q$insert into storage.objects (bucket_id, name)
              values ('other-bucket', '00000000-0000-4000-a000-0000000000a2/photo-a.jpg')$q$;
    raise exception 'FAIL: A wrote into an unmanaged bucket';
  exception when insufficient_privilege then null;
  end;

  execute 'select count(*) from storage.objects' into n;
  if n <> 1 then raise exception 'FAIL: user A sees % storage objects, expected 1', n; end if;
end
$verify$;

reset role;

-- ---------------------------------------------------------------------------
-- 3. User B: cannot see, read, or affect any of A's data
-- ---------------------------------------------------------------------------

set role authenticated;
set request.jwt.claims = '{"sub":"22222222-2222-4222-8222-222222222222","role":"authenticated"}';

insert into public.properties (id, name)
values ('00000000-0000-4000-b000-0000000000b1', 'RLS verify B');

insert into public.inspections (id, property_id, title)
values ('00000000-0000-4000-b000-0000000000b2', '00000000-0000-4000-b000-0000000000b1', 'B inspection');

insert into public.findings (id, inspection_id, photo_path, location_description)
values (
  '00000000-0000-4000-b000-0000000000b3',
  '00000000-0000-4000-b000-0000000000b2',
  'findings/00000000-0000-4000-b000-0000000000b2/photo-b.jpg',
  'B basement sump'
);

insert into storage.objects (bucket_id, name)
values ('findings', '00000000-0000-4000-b000-0000000000b2/photo-b.jpg');

do $verify$
declare
  n int;
begin
  -- Sees only its own rows (A created 2 properties, 1 inspection, 1 finding).
  execute 'select count(*) from public.properties' into n;
  if n <> 1 then raise exception 'FAIL: user B sees % properties, expected 1', n; end if;
  execute 'select count(*) from public.inspections' into n;
  if n <> 1 then raise exception 'FAIL: user B sees % inspections, expected 1', n; end if;
  execute 'select count(*) from public.findings' into n;
  if n <> 1 then raise exception 'FAIL: user B sees % findings, expected 1', n; end if;
  execute 'select count(*) from storage.objects' into n;
  if n <> 1 then raise exception 'FAIL: user B sees % storage objects, expected 1', n; end if;

  -- Cannot read A's rows even when it knows their ids.
  execute $q$select count(*) from public.properties
            where id = '00000000-0000-4000-a000-0000000000a1'$q$ into n;
  if n <> 0 then raise exception 'FAIL: user B read A''s property'; end if;
  execute $q$select count(*) from public.inspections
            where id = '00000000-0000-4000-a000-0000000000a2'$q$ into n;
  if n <> 0 then raise exception 'FAIL: user B read A''s inspection'; end if;
  execute $q$select count(*) from public.findings
            where id = '00000000-0000-4000-a000-0000000000a3'$q$ into n;
  if n <> 0 then raise exception 'FAIL: user B read A''s finding'; end if;
  execute $q$select count(*) from storage.objects
            where name = '00000000-0000-4000-a000-0000000000a2/photo-a.jpg'$q$ into n;
  if n <> 0 then raise exception 'FAIL: user B read A''s photo object'; end if;

  -- Cannot update or delete A's property (silently filtered => 0 rows).
  execute $q$update public.properties set name = 'hacked'
            where id = '00000000-0000-4000-a000-0000000000a1'$q$;
  get diagnostics n = row_count;
  if n <> 0 then raise exception 'FAIL: user B updated A''s property'; end if;

  execute $q$delete from public.properties
            where id = '00000000-0000-4000-a000-0000000000a1'$q$;
  get diagnostics n = row_count;
  if n <> 0 then raise exception 'FAIL: user B deleted A''s property'; end if;

  execute $q$delete from storage.objects
            where name = '00000000-0000-4000-a000-0000000000a2/photo-a.jpg'$q$;
  get diagnostics n = row_count;
  if n <> 0 then raise exception 'FAIL: user B deleted A''s photo object'; end if;

  -- Cannot attach children to A's chain.
  begin
    execute $q$insert into public.inspections (property_id, title)
              values ('00000000-0000-4000-a000-0000000000a1', 'B on A property')$q$;
    raise exception 'FAIL: B inserted an inspection under A''s property';
  exception when insufficient_privilege then null;
  end;

  begin
    execute $q$insert into public.findings (inspection_id, photo_path, location_description)
              values ('00000000-0000-4000-a000-0000000000a2',
                      'findings/00000000-0000-4000-a000-0000000000a2/b.jpg', 'B inject')$q$;
    raise exception 'FAIL: B inserted a finding under A''s inspection';
  exception when insufficient_privilege then null;
  end;
end
$verify$;

reset role;

-- ---------------------------------------------------------------------------
-- 4. A's data survived B's attempts, and B still cannot see A (post-attack)
-- ---------------------------------------------------------------------------

set role authenticated;
set request.jwt.claims = '{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated"}';

do $verify$
declare
  n int;
  prop_name text;
begin
  select count(*) into n from public.properties
  where id = '00000000-0000-4000-a000-0000000000a1';
  if n <> 1 then raise exception 'FAIL: A''s property disappeared'; end if;

  select name into prop_name from public.properties
  where id = '00000000-0000-4000-a000-0000000000a1';
  if prop_name <> 'RLS verify A' then
    raise exception 'FAIL: A''s property was modified (name=%)', prop_name;
  end if;

  -- A sees exactly its 2 properties / 1 inspection / 1 finding / 1 object.
  select count(*) into n from public.properties;
  if n <> 2 then raise exception 'FAIL: post-attack A sees % properties, expected 2', n; end if;
  select count(*) into n from public.inspections;
  if n <> 1 then raise exception 'FAIL: post-attack A sees % inspections, expected 1', n; end if;
  select count(*) into n from public.findings;
  if n <> 1 then raise exception 'FAIL: post-attack A sees % findings, expected 1', n; end if;
  select count(*) into n from storage.objects;
  if n <> 1 then raise exception 'FAIL: post-attack A sees % storage objects, expected 1', n; end if;
end
$verify$;

reset role;

-- ---------------------------------------------------------------------------
-- 5. service_role bypasses RLS (admin/report path intact)
-- ---------------------------------------------------------------------------

set role service_role;

do $verify$
declare
  n int;
begin
  execute 'select count(*) from public.properties' into n;
  if n <> 3 then raise exception 'FAIL: service_role sees % properties, expected 3', n; end if;
  execute 'select count(*) from public.inspections' into n;
  if n <> 2 then raise exception 'FAIL: service_role sees % inspections, expected 2', n; end if;
  execute 'select count(*) from public.findings' into n;
  if n <> 2 then raise exception 'FAIL: service_role sees % findings, expected 2', n; end if;
  execute 'select count(*) from storage.objects' into n;
  if n <> 2 then raise exception 'FAIL: service_role sees % storage objects, expected 2', n; end if;
end
$verify$;

reset role;

do $verify$
begin
  raise notice 'RLS verification passed';
end
$verify$;
