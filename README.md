# Lecture Indexer (LI)

Timestamped keyword search over recorded lectures. A professor registers a YouTube lecture; LI fetches its timed captions through the YouTube Data API and indexes them. A student searches a course for a term and gets every lecture and timestamp where it is spoken, linked straight to that moment (`youtube.com/watch?v=…&t=202s`).

CS 6030 Cloud Computing semester project, Western Michigan University, Fall 2026: Theodore Podewil, Joshua Jubenville, Andrew Wojciechowski.

## Architecture

| Layer | Service | Cloud |
|---|---|---|
| Front end | React SPA (nginx container) on Cloud Run | Google Cloud |
| Identity | Google Sign-In (OAuth 2.0 / OIDC) | Google Cloud |
| Application | Ingest API + Search API (Flask, Docker) on GKE with HPA | Google Cloud |
| Database | Cloud SQL for PostgreSQL, full-text search | Google Cloud |
| Backups | Nightly encrypted `pg_dump` to Blob Storage | Azure |
| Secrets / registry / monitoring | Secret Manager, Artifact Registry, Cloud Monitoring | Google Cloud |
| CI/CD / IaC | GitHub Actions (keyless OIDC), Terraform | both |

Full rationale: [the proposal](docs/milestones/m1_project_proposal/). The proposal put the front end on Azure Static Web Apps; our Azure subscription can't deploy it, so it moved to Cloud Run ([ADR 0001](docs/architecture_decision_records/0001-frontend-on-cloud-run.md)).

## Run locally

Linux (Ubuntu/Debian) or Windows through WSL2. Install these first:

| Tool | Version | Needed for |
|---|---|---|
| git, make, bash, curl, python3 | any recent | everything |
| Docker Engine with the Compose plugin | Compose v2.20+ | Postgres and both APIs (`make dev-up`) |
| Node.js with npm | 22.22+ | the frontend |
| [uv](https://docs.astral.sh/uv/) | latest | only Python tests and lint |

Install commands for each tool, the WSL2 setup, and troubleshooting are in **[docs/local-development.md](docs/local-development.md)**.

```sh
make doctor          # checks the tools above
# If your user isn't in the docker group: export COMPOSE="sudo docker compose"
make dev-up          # Postgres + migrations + Ingest API (:8081) + Search API (:8082)
make smoke           # end-to-end check of the running APIs

cp frontend/.env.example frontend/.env.local   # first time; dev sign-in
make frontend-install
make frontend-dev    # http://localhost:5173
```

Sign in as `prof@example.edu` (professor) or `student@example.edu`. Registering a lecture needs real Google sign-in, because the Ingest API calls YouTube with your token; see the [real Google test](docs/runbooks/real-google-test.md). Stop with `Ctrl-C` and `make dev-down`.

API reference and configuration: [services/README.md](services/README.md). Run `make help` for every target. CI (`.github/workflows/ci.yml`) runs the tests and checks on every push.

## Repository layout

| Path | Contents |
|---|---|
| `frontend/` | React + Vite + TypeScript app, served by nginx on Cloud Run |
| `services/` | uv workspace: `common/` (shared `li_common` package), `ingest/`, `search/` |
| `backup/` | `pg_dump` → encrypt → Azure Blob CronJob image |
| `db/migrations/` | Database schema migrations |
| `deploy/k8s/` | Kustomize manifests (`base/`, `overlays/prod/`) |
| `infra/terraform/` | `bootstrap/` (state + CI identities), `modules/`, `envs/prod/` |
| `.github/workflows/` | `ci.yml` (lint, tests, image builds, manifest, Terraform and document checks), `release.yml` and `rollback.yml` ([release process](docs/release-process.md)), `terraform.yml` (plan comments on pull requests), `wait-for-ci.yml` |
| `scripts/` | Dev, CI, backup and cost-control helpers |
| `docs/` | Proposal, [implementation plan](docs/implementation-plan.md), [architecture decision records](docs/architecture_decision_records/) (ADRs), runbooks, [security notes](docs/security/) (e.g. [database access](docs/security/database-access.md)), [how transcript search works](docs/search/transcript-search.md), milestone write-ups |
