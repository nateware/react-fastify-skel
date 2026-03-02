# Project Overview

React + Fastify monorepo skeleton using Turborepo and npm workspaces.

## Structure

- `frontend/` — React Router v7 with SSR, Vite, TypeScript, TailwindCSS
- `backend/` — Fastify v5 with TypeScript, ESM, fastify-cli

## Commands

All commands run from the repo root:

- `npm run dev` — start both dev servers (frontend :5173, backend :3001)
- `npm run build` — build both packages
- `npm run test` — run Vitest in both packages
- `npm run typecheck` — type-check both packages
- `npm run lint` — lint with Biome
- `npm run lint:fix` — auto-fix lint issues

Target a single workspace: `npm run <script> --workspace=frontend` or `--workspace=backend`

## Conventions

- Biome for linting and formatting (not ESLint/Prettier)
- Vitest for testing (both packages)
- Frontend tests use Testing Library + happy-dom
- Backend uses @fastify/autoload — plugins in `src/plugins/`, routes in `src/routes/`
- Vite proxies `/api` to the backend in dev — prefix backend routes with `/api`
- Dockerfiles use `turbo prune` for minimal images — build context is the repo root
- Install packages via `npm install <pkg> --workspace=frontend` (or `backend`)
