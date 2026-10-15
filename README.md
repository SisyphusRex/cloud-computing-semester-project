# Lecture Indexer (LI)

Timestamped keyword search over recorded lectures. A professor registers a YouTube lecture; LI fetches its timed captions through the YouTube Data API and indexes them. A student searches a course for a term and gets every lecture and timestamp where it is spoken, linked straight to that moment (`youtube.com/watch?v=…&t=202s`).

CS 6030 Cloud Computing semester project, Western Michigan University, Fall 2026: Theodore Podewil, Joshua Jubenville, Andrew Wojciechowski.

## Architecture

| Layer | Service | Cloud |
|---|---|---|
| Front end | React SPA on Static Web Apps | Azure |
| Identity | Google Sign-In (OAuth 2.0 / OIDC) | Google Cloud |
| Application | Ingest API + Search API (Flask, Docker) on GKE with HPA | Google Cloud |
| Database | Cloud SQL for PostgreSQL, full-text search | Google Cloud |
| Backups | Nightly encrypted `pg_dump` to Blob Storage | Azure |
| Secrets / registry / monitoring | Secret Manager, Artifact Registry, Cloud Monitoring | Google Cloud |
| CI/CD / IaC | GitHub Actions (keyless OIDC), Terraform | both |

Full rationale: [docs/proposal/](docs/proposal/).

## Quickstart

Needs [uv](https://docs.astral.sh/uv/getting-started/installation/), Docker, and Node 22.

```sh
make install   # Python environment for the services
make test-db   # all tests against a local Postgres container
make dev-up    # Postgres + migrations + ingest (:8081) + search (:8082)
make smoke     # end-to-end check of the running stack

cp frontend/.env.example frontend/.env.local   # dev sign-in by default
make frontend-install
make frontend-dev   # http://localhost:5173; sign in as prof@example.edu or student@example.edu
```

Dev sign-in can create courses and search, but registering a lecture needs real Google sign-in, because the Ingest API calls YouTube with your token; see the [implementation plan](docs/implementation-plan.md#next-real-googleyoutube-test-free-before-deploying).

API reference and configuration: [services/README.md](services/README.md). Run `make help` for every target. CI (`.github/workflows/ci.yml`) runs the same checks on every push.

## Repository layout

| Path | Contents |
|---|---|
| `frontend/` | React + Vite + TypeScript app, deployed to Azure Static Web Apps |
| `services/` | uv workspace: `common/` (shared `li_common` package), `ingest/`, `search/` |
| `backup/` | `pg_dump` → encrypt → Azure Blob CronJob image |
| `db/migrations/` | Database schema migrations |
| `deploy/k8s/` | Kustomize manifests (`base/`, `overlays/prod/`) |
| `infra/terraform/` | `bootstrap/` (state + CI identities), `modules/`, `envs/prod/` |
| `.github/workflows/` | `ci.yml` (lint, tests, image builds, manifest and Terraform checks); deploy workflows come with the first deployment |
| `scripts/` | Dev and cost-control helpers |
| `docs/` | Proposal, [implementation plan](docs/implementation-plan.md), ADRs, runbooks, milestone write-ups |
