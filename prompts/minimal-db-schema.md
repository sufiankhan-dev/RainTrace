# Minimal PostgreSQL schema: properties, inspections, findings

## Goal

Design and version-control the minimal RainTrace database schema on Supabase
(PostgreSQL): `properties`, `inspections`, `findings`. Include relationships,
UUID identifiers, timestamps, sensible constraints and indexes, and keep the
AI suggestion separate from the human-confirmed finding. No UI in this task.

## Inspected state

- Next.js 16 App Router, React 19, strict TypeScript, Tailwind v4, shadcn/ui.
- Supabase already wired via `@supabase/ssr` (`lib/supabase/*`); auth NOT
  implemented yet. `.env.example` documents `NEXT_PUBLIC_SUPABASE_URL`,
  `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`, optional `SUPABASE_SERVICE_ROLE_KEY`.
- No `supabase/` directory, no migrations, README states "no database schema".
- Tooling available: Supabase CLI v2.84.2 (`supabase.exe`), Docker 29 running
  with all Supabase images already pulled, so a local stack can verify the
  migration end to end.
- Repo conventions: plans live in `prompts/`; Postgres guidance from the
  bundled `supabase-postgres-best-practices` skill (index FKs, index RLS
  columns, `timestamptz`, text + check instead of varchar/enums, partial
  indexes, avoid v4 UUID fragmentation on large tables).

## Design decisions

- **UUID PKs** via `gen_random_uuid()` (core PG13+, guaranteed on Supabase).
  UUIDv7/pg_uuidv7 would be better for write-heavy tables but adds an extension
  dependency these small tables do not need.
- **`timestamptz` everywhere**, `now()` defaults, UTC storage. `observed_at`
  (when the condition was seen) is distinct from `created_at` (when the row /
  upload was recorded).
- **Relationships**: `inspections.property_id -> properties(id)` and
  `findings.inspection_id -> inspections(id)`, both `on delete cascade`
  (deleting a property removes its inspections and findings).
- **`created_by uuid references auth.users(id) on delete set null`** on all
  three tables (nullable until auth ships; `set null` keeps the record).
- **AI separation**: `category` + `confirmed_summary` hold the human-confirmed
  finding; the validated model suggestion lives in a separate `ai_suggestion`
  jsonb column with `ai_model_id`, `ai_prompt_version`, `ai_analyzed_at`
  traceability. A rerun can only rewrite the AI columns, never the confirmed
  ones. `review_status` (`pending | confirmed | corrected | rejected`) records
  how the suggestion was handled.
- **Category and status via `text` + CHECK** (not enum types) so the taxonomy
  can grow in a normal migration. Category is the human-confirmed value; the
  seven allowed values mirror `AGENTS.md` §4.
- **Location**: nullable `latitude`/`longitude` (numeric(9,6)) that must be
  both-present-or-both-absent, plus a `location_description` manual fallback.
  At least one form of location is required (MVP priority #4). No PostGIS yet —
  no geographic querying is in scope.
- **`photo_path`** is a storage object path, enforced as not-a-URL by CHECK.
- **`updated_at`** maintained by a shared `public.set_updated_at()` trigger
  with `search_path = ''` (passes the Supabase linter).
- **Indexes**: every FK column (`property_id`, `inspection_id`, `created_by`),
  per-property inspection history `(property_id, inspection_date desc)`,
  findings filters `(category, observed_at desc)` and `(observed_at desc)`, and
  a small partial index for report queries over confirmed findings.
  `created_by` indexes are partial (`where created_by is not null`).
- **RLS**: enabled on all three tables, a single owner policy per table
  (`for all to authenticated using ((select auth.uid()) = created_by)` with a
  matching `with check`). `anon` is revoked and has no policy → default deny.
  `service_role` keeps full access for trusted server-side work.
- Auth is not implemented yet, so until it is, any app read/write must go
  through the server-only service-role client (`lib/supabase/admin.ts`).
  Documented, not hidden.

## Files to change

- `supabase/config.toml` + `supabase/.gitignore` (new, from `supabase init`)
- `supabase/migrations/<timestamp>_initial_schema.sql` (new migration)
- `prompts/minimal-db-schema.md` (this plan)
- `README.md` (status line + database/migration section)

## Security considerations

- RLS is the access-control boundary, not the UI. Table owner and
  `service_role` bypass it; `anon`/`authenticated` cannot read other users'
  rows, and `anon` cannot read anything.
- No secrets in the migration. No real Supabase project is touched; verification
  runs only against the local Docker stack.
- `auth.users` is only referenced, never modified.

## Acceptance criteria

- Migration applies cleanly on a fresh local Supabase database.
- Deleting a property cascades to inspections and findings.
- Invalid category, out-of-range/paired coordinates, missing location, blank or
  URL `photo_path`, `confirmed`/`corrected` without category+summary, and
  `ai_suggestion` without model id/analyzed_at are all rejected.
- AI suggestion columns never overwrite confirmed columns (separate columns).
- `updated_at` advances on UPDATE.
- RLS: `anon` sees zero rows; an `authenticated` user sees only their own rows;
  `service_role` sees all.
- `supabase db advisors` reports no schema lints for these objects.
- `npm run lint` and `npx tsc --noEmit` still pass (no TS changes expected).

## Checks and manual test steps

1. `supabase start` then `supabase db reset` — applies the migration.
2. Insert/select via `supabase db query` as `service_role` (bypasses RLS).
3. Attempt each invalid row above and confirm the rejection.
4. `set role anon` → expect zero rows on all three tables.
5. `supabase db advisors` → no findings for these tables.
6. `npm run lint` and `npx tsc --noEmit`.
