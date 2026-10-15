# RainTrace

Open-source AI-assisted water and drainage inspection tool for property managers, housing societies, and maintenance contractors.

> **Status:** foundation, Supabase client, and the initial database schema. The version-controlled migration defines `properties`, `inspections`, and `findings` with Row Level Security. Authentication, AI inference, and the inspection features/UI are not implemented yet.

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

The schema is version-controlled in `supabase/migrations/`. The initial migration
(`20261015135508_initial_schema.sql`) defines three tables:

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
- Row Level Security is enabled on all three tables. `authenticated` users can
  only access rows they created; `anon` has no access; `service_role`
  (server-only) bypasses RLS. Authentication is not implemented yet, so app
  reads/writes must currently go through the server-only service-role client
  (`lib/supabase/admin.ts`) until sign-in is added.

Apply the schema locally (requires Docker):

```bash
supabase start       # start the local Supabase stack
supabase db reset    # (re)apply all migrations + seed
```

Apply it to a hosted project:

```bash
supabase link --project-ref <your-project-ref>
supabase db push
```

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
