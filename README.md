# RainTrace

Open-source AI-assisted water and drainage inspection tool for property managers, housing societies, and maintenance contractors.

> **Status:** project foundation only. No database, AI inference, authentication, or inspection features are implemented yet.

## Stack

- [Next.js](https://nextjs.org) (App Router) with React and strict TypeScript
- [Tailwind CSS](https://tailwindcss.com) v4
- [shadcn/ui](https://ui.shadcn.com) components (`components.json` style: `base-nova`)
- Package manager: npm

## Getting started

```bash
npm install
npm run dev
```

Open [http://localhost:3000](http://localhost:3000).

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
