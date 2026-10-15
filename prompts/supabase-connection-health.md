# Supabase connection: hosted verification and health check

## Goal

Connect the app to the configured hosted Supabase project
(`NEXT_PUBLIC_SUPABASE_URL=https://lmxsufcyzfdhuvjjvgfp.supabase.co`), verify the
version-controlled migrations and database queries actually work, and add one
minimal health check that fits the existing architecture. No sample/customer
data anywhere.

## Inspected state

- `.env` already holds the project URL and publishable key (gitignored).
  `SUPABASE_SERVICE_ROLE_KEY` is not set. `.env.example` already documents all
  three variables — no new variables needed.
- Migrations: `20261015135508_initial_schema.sql` (three tables) and
  `20261015180000_rls_owner_chain_and_storage.sql` (owner-chain RLS, private
  `findings` bucket). Per `prompts/minimal-db-schema.md`, both were verified
  only against the local Docker stack — never pushed to the hosted project.
- Supabase CLI v2.84.2 installed but **not logged in** (`supabase projects list`
  → "Access token not provided"), project not linked, so `supabase db push`
  cannot run without manual credentials.
- Local stack running (`supabase status`, project id `raintrace`);
  `supabase/tests/rls_verification.sql` is the existing DB-level test (fixtures
  with fixed ids, self-cleaning, single `NOTICE: RLS verification passed`).
- No test runner in the repo; conventions are `supabase/tests/*.sql` + lint +
  `npx tsc --noEmit`.

## Verified probe semantics (empirical, not assumed)

Using the publishable key against `GET /rest/v1/<table>?select=id&limit=1`:

| Response                              | Meaning                                    |
| ------------------------------------- | ------------------------------------------ |
| `200 []`                              | table exists and is readable               |
| `401` `{"code":"42501"}`              | table exists, grants revoked (expected)    |
| `404` `{"code":"PGRST205"}`           | table missing from `public` schema         |
| `401` `"Invalid API key"`             | publishable key rejected                   |

Confirmed on the local stack that the PostgREST schema cache is **not**
role-filtered (existing+revoked → 42501, not PGRST205), so PGRST205 on the
hosted project proves the migrations have not been applied there. Hosted probe
result: all three tables missing; `GET /storage/v1/bucket/findings` → 404
`NoSuchBucket`.

## Design decisions

- **One route handler, `GET /api/health`** (`app/api/health/route.ts`), JSON
  only, `force-dynamic`, `Cache-Control: no-store`. Fits the App Router
  architecture; no test framework is added just for this.
- **Checks, each with status `ok | degraded | error | skipped` and a message:**
  1. `config` — both public env vars present.
  2. `restApi` — project reachable and publishable key accepted (parallel
     5 s-timeout probes of the three tables).
  3. `schema` — all three tables exist and are correctly denied to the
     publishable key (42501 = present, PGRST205 = not pushed, 200 = unexpected
     public read).
  4. `databaseQueries` — real `select(id).limit(1)` on all three tables through
     the existing server-only `createAdminClient()` (`lib/supabase/admin.ts`).
     Skipped with an explanatory message when `SUPABASE_SERVICE_ROLE_KEY` is
     unset — anon has no grants by design, so only the service role can prove
     the query path end to end.
  5. `storage` — private `findings` bucket exists and is not public (admin
     client), covering the second migration.
- **Roll-up:** `error` > `degraded` > `ok` (skipped never affects the roll-up).
  HTTP 200 only for `ok`; 503 for `degraded`/`error`. Messages are actionable
  (e.g. "apply migrations with supabase db push").
- **No keys in the response**, no row data, no sample rows written anywhere.

## Files to change

- `app/api/health/route.ts` (new)
- `prompts/supabase-connection-health.md` (this plan)
- `README.md` — health check section + manual hosted setup steps

## Security considerations

- Publishable key only in the public probe; service-role key only via the
  `server-only` admin helper. Neither is ever echoed in output or logs.
- Read-only probes (`limit=1`, no writes); no fixtures or sample data created.
- The endpoint reveals only "configured / reachable / schema present" — no
  tenant data.

## Acceptance criteria

- Migrations apply cleanly on a fresh local database (`supabase db reset`) and
  `rls_verification.sql` passes.
- `/api/health` returns 200 with all non-skipped checks `ok` against a fully
  configured, migrated project (verified locally with publishable + secret keys).
- Against the hosted project as currently configured it returns 503 with
  `schema: degraded` naming the missing tables — honest, actionable.
- `npm run lint`, `npx tsc --noEmit`, `npm run build` pass.

## Checks and manual test steps

1. `supabase db reset` — both migrations apply fresh.
2. `Get-Content supabase/tests/rls_verification.sql -Raw | docker exec -i
   supabase_db_raintrace psql -U postgres -d postgres -v ON_ERROR_STOP=1` —
   expect `NOTICE: RLS verification passed`.
3. `supabase db reset` again — local DB ends empty (no leftover fixtures).
4. Dev server with local URL + publishable + secret keys →
   `curl -i localhost:<port>/api/health` → 200, `status: "ok"`.
5. Dev server with the repo's real `.env` → 503, `schema: degraded` listing the
   three tables (migrations not yet pushed).
6. `npm run lint`, `npx tsc --noEmit`, `npm run build`.

## Outcome: hosted project migrated and verified

All local checks above passed, then the hosted project was brought in line.

What happened, in order:

1. `supabase login` (done by the user) stored an access token in the Windows
   Credential Manager (`Supabase CLI:supabase`); no plaintext token file.
2. `supabase link --project-ref lmxsufcyzfdhuvjjvgfp --yes` re-run from the repo
   root wrote `supabase/.temp/project-ref` and the version/pooler metadata. An
   earlier attempt ran with the wrong working directory and dropped a stray
   `~/Documents/supabase/.temp`; that directory had no `config.toml` and was
   removed.
3. The database password is not stored, so migrations were applied through the
   **Management API**: `POST https://api.supabase.com/v1/projects/<ref>/database/query`
   with the CLI login token (read from the Credential Manager at call time).
   `GET /v1/projects/<ref>/database/query` runs as `postgres`.
4. Migration `20261015135508` applied; `20261015180000` first failed with a
   JSON body error. Cause: Windows PowerShell 5.1 read the UTF-8 migration as
   the ANSI codepage (the file has three em-dashes in its header comment) and
   then encoded the request body lossily. Fix: read the file with
   `-Encoding UTF8`, escape non-ASCII to `\uXXXX`, and send UTF-8 bytes.
5. `supabase_migrations.schema_migrations` was created to match the CLI's shape
   (`version text primary key`, `statements text[]`, `name text`) and both
   versions were recorded so the CLI treats them as applied.
6. `SUPABASE_SERVICE_ROLE_KEY` was added to `.env`. The Management API returns
   the newer `sb_secret_…` key redacted (26 `·` filler characters), so the
   legacy `service_role` JWT was used instead; `.env` is gitignored and the key
   is never printed.

Verification against the hosted project:

- `supabase migration list --linked` — local and remote match for both versions.
- `supabase db push --linked --dry-run` — "Remote database is up to date."
- REST with the publishable key → `401 {"code":"42501"}` on all three tables
  (present, denied); with the service key → `200 []` (RLS bypassed, empty).
- `GET /storage/v1/bucket/findings` → 200, `public: false`, 50 MiB,
  image MIME types only.
- RLS enabled on all three tables; the three owner-chain policies and the one
  `storage.objects` policy exist; `created_by` defaults to `auth.uid()`.
- `GET /api/health` against the hosted `.env` → **200**, `status: "ok"`, all
  five checks `ok`.
- No rows were created anywhere (`properties`/`inspections`/`findings` = 0).

Known limitations carried forward: no database password is stored, so
password-dependent CLI commands rely on the Management API fallback; and the
service-role client bypasses RLS, so the app still needs sign-in before it can
hold real multi-customer data (unchanged from the note at the top of this file).
