# Foundation setup — Next.js / TypeScript / Tailwind / shadcn/ui

## Goal

Complete and verify the project foundation only: Next.js App Router, TypeScript (strict), Tailwind CSS, and shadcn/ui. No database, AI, authentication, or business features.

## Inspected state

- Next.js 16.4.1 App Router scaffold (`app/layout.tsx`, `app/page.tsx`, `app/globals.css`) — present.
- TypeScript strict with `@/*` path alias — present (`tsconfig.json`).
- Tailwind CSS 4.3.3 wired via `@tailwindcss/turbopack` loader in `next.config.ts` — present.
- shadcn/ui — missing: no `components.json`, no `lib/utils.ts`, no `components/ui/*`, no shadcn dependencies.
- Package manager: npm (`package-lock.json`).
- README still create-next-app boilerplate; layout metadata still "Create Next App".

## Design decisions

- Use the official shadcn CLI (`npx shadcn@latest init`) against the existing project so generated config matches the installed Tailwind v4 + React 19 setup.
- Base color: neutral; style: new-york (shadcn defaults for new projects).
- Add only two starter components (`button`, `card`) — enough to prove the pipeline; more added per-feature later.
- Replace the boilerplate home page with a minimal RainTrace landing that renders shadcn components (verifies styling end-to-end).
- Update metadata and README to reflect the actual project. No fake data or metrics.

## Files to change

- `components.json` (new, CLI-generated)
- `lib/utils.ts` (new, `cn` helper)
- `components/ui/button.tsx`, `components/ui/card.tsx` (new, CLI-generated)
- `app/globals.css` (shadcn theme variables appended by CLI)
- `app/layout.tsx` (RainTrace metadata)
- `app/page.tsx` (minimal landing using shadcn components)
- `README.md` (project-specific setup notes)
- `package.json` / `package-lock.json` (shadcn runtime deps)

## Security considerations

- No secrets involved. No env vars needed for this step.

## Acceptance criteria

- `npm run lint` passes.
- `npx tsc --noEmit` passes.
- `npm run build` succeeds.
- Home page renders with shadcn Button and Card using Tailwind utilities.

## Checks and manual test steps

1. `npm run lint`
2. `npx tsc --noEmit`
3. `npm run build`
4. `npm run dev` → open http://localhost:3000 → verify RainTrace landing page with styled components.
