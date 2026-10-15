# RainTrace

Open-source AI-assisted water and drainage inspection tool for property managers, housing societies, and maintenance contractors.

> **Status:** foundation, Supabase client, the database schema, hardened data-access policies, and a `/api/health` connection check. The version-controlled migrations define `properties`, `inspections`, and `findings` with Row Level Security, plus a private `findings` storage bucket and its policies; both migrations are applied to the linked hosted project and `/api/health` reports `ok` there. Authentication, AI inference, and the inspection features/UI are **not implemented yet**, so the running app has no per-user isolation until sign-in ships (see [Row Level Security](#row-level-security)).

## Stack

- [Next.js](https://nextjs.org) (App Router) with React and strict TypeScript
- [Tailwind CSS](https://tailwindcss.com) v4
- [shadcn/ui](https://ui.shadcn.com) components (`components.json` style: `base-nova`)
- [Supabase](https://supabase.com) via `@supabase/supabase-js` + `@supabase/ssr`
- Package manager: npm

## Getting started

```bash
npm install
cp .env.example .env.local   # then fill in your Supabase values
npm run dev
```

Open [http://localhost:3000](http://localhost:3000).

## Environment variables

Copy `.env.example` to `.env.local` and set the values for your Supabase project. The app starts without them — Supabase is simply treated as unconfigured — but any Supabase client usage will report a clear error until they are set.

| Variable                             | Required | Exposed to browser | Purpose                                                                 |
| ------------------------------------ | -------- | ------------------ | ----------------------------------------------------------------------- |
| `NEXT_PUBLIC_SUPABASE_URL`           | Yes\*    | Yes                | Supabase project URL.                                                    |
| `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` | Yes\*  | Yes                | Supabase publishable (client) key; safe for the browser.                 |
| `SUPABASE_SERVICE_ROLE_KEY`          | No       | No (server-only)   | Privileged key for trusted server-side admin tasks only.                 |

\*Required only once Supabase-backed features are used.

Notes:

- Only `NEXT_PUBLIC_*` variables are inlined into the browser bundle. Never prefix the service-role key with `NEXT_PUBLIC_`.
- The service-role key bypasses Row Level Security. It is read only in `lib/supabase/admin.ts`, which is guarded by `server-only` so it cannot be imported into Client Components.
- `SUPABASE_SERVICE_ROLE_KEY` accepts either the legacy `service_role` JWT or a newer `sb_secret_…` key. The Management API (`GET /v1/projects/<ref>/api-keys`) returns the secret key redacted, so if you use one, copy it from the dashboard when it is created.
- Real `.env.local` files are gitignored; only the placeholder `.env.example` is committed.

## Supabase client

Setup follows the official `@supabase/ssr` approach for the Next.js App Router:

- `lib/supabase/config.ts` — reads/validates the public env vars and exposes `isSupabaseConfigured`, `getSupabaseConfig()`, and `requireSupabaseConfig()`.
- `lib/supabase/client.ts` — `createClient()` for Client Components (`createBrowserClient`).
- `lib/supabase/server.ts` — `createClient()` for Server Components, Server Actions, and Route Handlers (`createServerClient` + `cookies()`); `server-only`.
- `lib/supabase/admin.ts` — optional service-role client; `server-only`; returns `null` when unconfigured.
- `proxy.ts` — refreshes the auth session on each request (Next.js 16's `middleware`). No-ops when Supabase is unconfigured.

Clients throw a descriptive, actionable error only when actually created without configuration, so a missing setup never breaks the build or existing pages.

## Database schema

The schema is version-controlled in `supabase/migrations/`. Two migrations define
the data and its access rules:

- `20261015135508_initial_schema.sql` — the three tables.
- `20261015180000_rls_owner_chain_and_storage.sql` — owner-chain RLS policies,
  server-derived ownership, and the private photo bucket.

Tables:

- `properties` — a managed site.
- `inspections` — an inspection event for one property (`on delete cascade`).
- `findings` — a photo-backed observation within an inspection (`on delete cascade`).

Design highlights:

- UUID primary keys (`gen_random_uuid()`), `timestamptz` timestamps, foreign keys,
  and CHECK constraints throughout.
- AI output is kept separate from human-confirmed data: `category` and
  `confirmed_summary` are the inspector-confirmed finding, while `ai_suggestion`
  (jsonb) plus `ai_model_id`, `ai_prompt_version`, and `ai_analyzed_at` record the
  model suggestion. Re-running AI never overwrites confirmed fields.
- `observed_at` (when the condition was seen) is distinct from `created_at`
  (when the row was recorded).
- `created_by` defaults to `auth.uid()`, so ownership is derived server-side for
  signed-in users instead of being trusted from the request. It stays nullable
  for `service_role`/admin rows and legacy pre-auth data.
- `photo_path` stores a storage object path (`findings/<inspection_id>/<file>`),
  never a public URL.

### Row Level Security

RLS is enabled on all three tables and on `storage.objects`, and is the
access-control boundary — hidden UI is never the boundary.

- **Owner-chain policies.** A signed-in user can only read or write a row when
  they created it **and** they own the whole parent chain: an `inspection` must
  belong to a `property` they own, and a `finding` must belong to an `inspection`
  they own under a `property` they own. This matters because foreign keys are not
  covered by RLS on their own — without the chain check, a user could attach
  inspections or findings to someone else's records.
- **Photos.** A private `findings` bucket (no public access, image MIME types
  only, 50 MiB limit). Object names are `<inspection_id>/<file>`, and the storage
  policy only allows reading or writing an object whose first path segment is an
  inspection the caller owns. Reports and previews should use short-lived signed
  URLs generated server-side, not public bucket URLs.
- `anon` has no policies and no table grants, so anonymous requests get nothing.
- `service_role` bypasses RLS by design and stays server-only
  (`lib/supabase/admin.ts`); it is used for trusted server work such as signed-URL
  creation and admin cleanup.

**Authentication is not implemented yet, so this isolation is not active in the
app.** Policies only apply to requests that arrive as the `authenticated` role;
today no such requests exist, and any app-side database access must go through the
privileged service-role client, which bypasses RLS. Until sign-in ships — and rows
are created by authenticated users rather than the service role — do **not**
deploy real multi-customer data. Rows written by the service role have a `NULL`
`created_by` and are invisible to `authenticated` users; they would need a
one-off backfill once user accounts exist. Other known limits: the storage service
enforces MIME type from the client-declared `content_type` and the policy checks
the file extension, but no content sniffing is performed; location is
user-provided and never inferred from a photo.

### Verifying RLS

`supabase/tests/rls_verification.sql` proves the behaviour above: it seeds two
throwaway users (A and B), then checks that `anon` gets nothing, that A and B see
only their own rows, that B cannot read/update/delete A's rows or attach rows to
A's property or inspection, that cross-user photos are rejected, and that
`service_role` still sees everything. It raises an exception (non-zero exit) on
any mismatch.

Apply the schema locally (requires Docker):

```bash
supabase start       # start the local Supabase stack
supabase db reset    # (re)apply all migrations
```

Then run the verification script (PowerShell, from the repo root):

```powershell
Get-Content supabase/tests/rls_verification.sql -Raw |
  docker exec -i supabase_db_raintrace psql -U postgres -d postgres -v ON_ERROR_STOP=1
# Expected final line: NOTICE:  RLS verification passed
```

The script is re-runnable; it cleans up its own fixtures first. As a negative
control, weaken a policy (e.g. drop the parent chain from `inspections_owner_all`),
re-run — it should fail — then `supabase db reset` to restore.

Apply it to a hosted project:

```bash
supabase login
supabase link --project-ref <your-project-ref>
supabase db push
```

The linked hosted project (`lmxsufcyzfdhuvjjvgfp`) already has both migrations
applied; `supabase migration list --linked` shows local and remote in sync and
`supabase db push` reports "Remote database is up to date". Re-running `db push`
after adding a migration applies only the new one.

Up-to-date check without a stored database password:

```bash
supabase link --project-ref <your-project-ref> --yes   # uses the CLI login token
supabase migration list --linked
```

If `supabase db push` cannot reach the database (no password available for a
non-interactive shell), the same SQL can be applied through the Management API
`POST /v1/projects/<ref>/database/query` with a personal access token, then
recorded in `supabase_migrations.schema_migrations` (`version`, `name`) so the
CLI still sees it as applied. See `prompts/supabase-connection-health.md`.

## Health check

`GET /api/health` is a read-only connection check (`app/api/health/route.ts`).
It never writes data and never returns keys or row contents.

```bash
curl -i http://localhost:3000/api/health
```

| Check              | What it proves                                                                                                                                             |
| ------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `config`           | Both public Supabase env vars are present.                                                                                                                 |
| `restApi`          | The project is reachable and the publishable key is accepted.                                                                                              |
| `schema`           | `properties`, `inspections`, `findings` exist in `public` and are correctly denied to the publishable key (`42501`). `PGRST205` means migrations not applied. |
| `databaseQueries`  | Real `SELECT … LIMIT 1` queries on all three tables via the server-only service-role client. Skipped (with an explanatory message) when `SUPABASE_SERVICE_ROLE_KEY` is unset, because `anon` has no grants by design. |
| `storage`          | The private `findings` bucket exists and is not public (service-role client).                                                                               |

Each check reports `ok`, `degraded`, `error`, or `skipped` with an actionable
message. The overall `status` is `error` > `degraded` > `ok` (`skipped` never
affects it): HTTP **200** only when everything is `ok`, otherwise **503**.
Against a project where the migrations have not been pushed yet it returns 503
with `schema: degraded` naming the missing tables — run `supabase db push` and
re-check. Against the linked hosted project (with `SUPABASE_SERVICE_ROLE_KEY`
set) it returns **200** with all five checks `ok`.

## Scripts

| Script          | Purpose                     |
| --------------- | --------------------------- |
| `npm run dev`   | Development server          |
| `npm run build` | Production build            |
| `npm start`     | Serve production build      |
| `npm run lint`  | ESLint                      |

Type checking: `npx tsc --noEmit`

## Conventions

- App code lives in `app/`; shared helpers in `lib/`; UI components in `components/ui/` (shadcn).
- Path alias `@/*` maps to the repository root.
- Feature planning notes live in `prompts/`.
- See `AGENTS.md` for the full engineering workflow, AI safety rules, and product scope.
