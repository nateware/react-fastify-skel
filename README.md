# react-fastify-skel

A monorepo skeleton for building full-stack apps with React and Fastify.

## Tech Stack

- **Frontend** — React 19, React Router v7 (SPA), Vite, TailwindCSS, TypeScript
- **Backend** — Fastify v5, TypeScript, ESM
- **Monorepo** — Turborepo, npm workspaces
- **Testing** — Vitest, Testing Library
- **Linting** — Biome
- **Containers** — Docker with turbo prune, docker-compose
- **Deploy** — GCP (Cloud Run, GCS + CDN), GitHub Actions, staging + production

## Getting Started

```bash
# Use the correct Node version
nvm use

# Install dependencies
npm install

# Start both dev servers
npm run dev
```

Frontend runs at `http://localhost:5173`, backend at `http://localhost:3001`.

The Vite dev server proxies `/api` requests to the backend automatically.

## Scripts

| Command | Description |
|---|---|
| `npm run dev` | Start frontend + backend dev servers |
| `npm run build` | Build both packages |
| `npm run test` | Run all tests |
| `npm run typecheck` | Type-check both packages |
| `npm run lint` | Lint with Biome |
| `npm run lint:fix` | Auto-fix lint issues |
| `npm run format` | Format all files |
| `npm run clean` | Remove build artifacts and node_modules |

Target a single workspace with `--workspace=frontend` or `--workspace=backend`.

## Adding Dependencies

```bash
npm install <package> --workspace=frontend
npm install <package> --workspace=backend
```

## Docker

Build and run both services:

```bash
docker compose up --build
```

Build independently:

```bash
docker build -f frontend/Dockerfile -t myapp-frontend .
docker build -f backend/Dockerfile -t myapp-backend .
```

Frontend serves on port 3000, backend on port 3001.

## Project Structure

```
├── frontend/          React Router app
│   ├── app/           Routes and components
│   ├── test/          Test setup
│   └── Dockerfile
├── backend/           Fastify API server
│   ├── src/
│   │   ├── plugins/   Fastify plugins (auto-loaded)
│   │   └── routes/    Route handlers (auto-loaded)
│   ├── test/          API tests
│   └── Dockerfile
├── turbo.json         Turborepo task config
├── biome.json         Linter/formatter config
└── docker-compose.yml
```

## GCP Deployment

### Environments

| Environment | Trigger | Backend | Frontend |
|---|---|---|---|
| **staging** | Auto on push to `main` (after CI passes) | Cloud Run (`backend`) | GCS bucket + CDN |
| **production** | GitHub release published | Cloud Run (`backend`) | GCS bucket + CDN |

Each environment uses a separate GCP project for full isolation.

Manual deploys are available via `workflow_dispatch` on any workflow.

### Initial Setup

```bash
# 1. Edit configuration variables in the script (project IDs, region, GitHub org)
vi scripts/gcp_setup.sh

# 2. Set up each environment (separate GCP projects)
./scripts/gcp_setup.sh staging
./scripts/gcp_setup.sh production
```

After each run, configure the printed values as GitHub Environment Variables:
- Go to: Repo → Settings → Environments → `<env>` → Add variable
- Variables: `GCP_PROJECT_ID`, `GCP_REGION`, `WIF_PROVIDER`, `WIF_SERVICE_ACCOUNT`, `CORS_ORIGIN`, `VITE_API_URL`, `GCS_BUCKET`, `CDN_URL_MAP`

### Deploy Flow

```
Push to main → CI (lint, test, build) → Staging auto-deploy
                                           ↓
                              Verify staging looks good
                                           ↓
                              Create GitHub release → Production deploy
```

### SPA vs SSR

The frontend defaults to SPA mode (`ssr: false`), serving static files from GCS + CDN.

To switch to SSR mode:
1. Set `ssr: true` in `frontend/react-router.config.ts`
2. In `.github/workflows/_deploy_frontend.yml`, comment out the `deploy-spa` job and uncomment `deploy-ssr`

## Using as a Template

1. Clone or fork this repo
2. Update `name` in root `package.json`, `frontend/package.json`, and `backend/package.json`
3. Replace the example routes in `frontend/app/routes/` and `backend/src/routes/`
4. Update `.env.example` files with your environment variables
5. Edit `scripts/gcp_setup.sh` with your GCP project details
6. Run `npm install` and `npm run dev`
