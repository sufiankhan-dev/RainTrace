# App shell and navigation

## Goal

Build the responsive RainTrace application shell: persistent navigation for Overview, Properties, Inspections, and Reports; a clean professional facilities-management look; mobile-friendly navigation. Placeholder content only — no real data, database, auth, or AI.

## Inspected state

- Next.js 16.4.1 App Router, React 19, TypeScript strict, Tailwind CSS v4 (`@tailwindcss/turbopack`), shadcn/ui (style `base-nova`, base UI primitives via `@base-ui/react`), lucide-react icons.
- Existing shadcn components: `button`, `card` only. `components.json` aliases `@/components`, `@/lib`.
- Root layout sets Geist fonts, RainTrace metadata; `app/page.tsx` is a single foundation landing page.
- Package manager: npm. No `.env` needed.

## Design decisions

- Route group `app/(app)` holds all authenticated-app pages behind a shared shell layout so the root layout stays minimal.
- Routes: `/` (Overview), `/properties`, `/inspections`, `/reports`.
- Desktop (md+): fixed-width left sidebar with brand, primary nav, and footer note; content area scrolls.
- Mobile (<md): sticky top header with menu button opening a shadcn Sheet containing the same nav; no bottom bar (keep it simple for field use).
- Nav active state via `usePathname()` in a small client `NavLink` component; sidebar/sheet remain server components except the trigger.
- Add shadcn `sheet`, `separator`, `badge` via the official CLI to match the installed base-nova registry.
- Placeholder pages: short page header (title + one-line description) and a muted "coming soon" card — clearly labeled as placeholders, no fake metrics or data.
- Visual language: neutral zinc tones from existing theme, subtle borders, icon + label nav rows, restrained — an operations tool, not a marketing dashboard.

## Files to change

- `components/ui/sheet.tsx`, `components/ui/separator.tsx`, `components/ui/badge.tsx` (CLI-generated)
- `components/shell/nav-items.ts` (shared nav item list)
- `components/shell/nav-link.tsx` (client, active link)
- `components/shell/app-sidebar.tsx` (sidebar content: brand, nav, footer)
- `components/shell/mobile-header.tsx` (client: menu button + Sheet)
- `components/shell/app-shell.tsx` (composes sidebar + mobile header + main)
- `app/(app)/layout.tsx` (shell layout)
- `app/(app)/page.tsx` (Overview placeholder — replaces old `app/page.tsx`)
- `app/(app)/properties/page.tsx`, `app/(app)/inspections/page.tsx`, `app/(app)/reports/page.tsx`
- Delete old `app/page.tsx`

## Security considerations

- No secrets, no data access, no user input. Client components limited to navigation UI.

## Acceptance criteria

- All four routes render inside the shell with correct active nav highlighting.
- Desktop shows sidebar; mobile shows top header with working Sheet menu (open, navigate, close).
- `npm run lint`, `npx tsc --noEmit`, `npm run build` pass.
- Layout verified at mobile (~375px) and desktop (~1280px) widths.

## Checks and manual test steps

1. `npm run lint`
2. `npx tsc --noEmit`
3. `npm run build`
4. `npm run dev` → desktop: sidebar visible, nav works; mobile viewport: header + sheet menu works, no horizontal overflow.
