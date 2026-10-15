# Supabase client setup

## Goal

Set up the Supabase client using the official `@supabase/ssr` approach for the
installed Next.js 16 App Router, add an `.env.example` with placeholder values,
document the required environment variables, keep secrets server-side, and make
the app degrade gracefully when Supabase is not configured. No product features.

## Inspected state

- Next.js 16.4.1 App Router, React 19, TypeScript strict, Tailwind v4, shadcn/ui.
- `app/`, `components/`, `lib/` at repo root; path alias `@/*` → repo root.
- No Supabase packages installed; no `.env*` files; `.gitignore` ignores `.env*`.
- Existing conventions: small server components, shadcn primitives, feature plans
  in `prompts/`.
- Official Supabase docs (fetched) recommend `@supabase/supabase-js` +
  `@supabase/ssr` with `createBrowserClient` (client) and `createServerClient`
  (server, cookie-based). Env vars are `NEXT_PUBLIC_SUPABASE_URL` and
  `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` (publishable key supersedes anon key).
- Next.js 16 renamed `middleware.ts` to `proxy.ts` (export `proxy`). Supabase's
  official Next.js SSR setup uses this proxy to refresh sessions.

## Design decisions

- Install `@supabase/supabase-js`, `@supabase/ssr`, and `server-only`.
- `lib/supabase/config.ts`: single place that reads `NEXT_PUBLIC_SUPABASE_URL`
  and `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`. Exports `isSupabaseConfigured`,
  `getSupabaseConfig()` (returns `null` when unconfigured), and
  `requireSupabaseConfig()` (throws a descriptive error only when a client is
  actually created). No import-time throw, so missing config never crashes the
  build or existing pages.
- `lib/supabase/client.ts`: `createClient()` using `createBrowserClient` for
  Client Components (singleton handled by the library).
- `lib/supabase/server.ts`: `import "server-only"`; async `createClient()` using
  `createServerClient` with `cookies()` from `next/headers`. `setAll` writes via
  the cookie store and ignores the "called from Server Component" error.
- `lib/supabase/admin.ts`: `import "server-only"`; optional service-role client
  used only for privileged server tasks. Reads `SUPABASE_SERVICE_ROLE_KEY`,
  returns `null` when absent. The service-role key is never referenced in any
  client bundle.
- `proxy.ts` (root): official session-refresh proxy. No-ops (passes the request
  through) when Supabase is unconfigured so an unconfigured app still serves.
- `.env.example` with placeholders only; un-ignore it in `.gitignore`.
- README: environment variable table + security notes + missing-config behavior.

## Files to change

- `package.json` / `package-lock.json` (add dependencies)
- `lib/supabase/config.ts` (new)
- `lib/supabase/client.ts` (new)
- `lib/supabase/server.ts` (new)
- `lib/supabase/admin.ts` (new)
- `proxy.ts` (new)
- `.env.example` (new)
- `.gitignore` (allow `.env.example`)
- `README.md` (document env vars and setup)

## Security considerations

- Only `NEXT_PUBLIC_*` values are available to the browser; the service-role key
  is read exclusively in `lib/supabase/admin.ts`, guarded by `server-only`.
- `.env.example` contains placeholders only; real `.env*` files stay ignored.
- No secrets logged. Error messages name the missing variable, not its value.
- Proxy returns the refreshed cookies and cache headers from `setAll` so a CDN
  cannot cache a session response for another user.

## Acceptance criteria

- `npm run lint`, `npx tsc --noEmit`, and `npm run build` pass.
- App builds and serves with no Supabase env configured (graceful degradation).
- `createClient()` helpers throw a clear, actionable error when invoked without
  configuration; nothing throws at import time.
- `.env.example` is tracked; `.env`/`.env.local` remain ignored.

## Checks and manual test steps

1. `npm run lint`
2. `npx tsc --noEmit`
3. `npm run build` (no env set — must succeed)
4. `npm run dev` → open http://localhost:3000 → existing shell still renders.
5. Copy `.env.example` to `.env.local`, fill real values, restart `npm run dev`
   → no errors; proxy no longer no-ops.
