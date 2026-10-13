# Implementation plan

Living plan for building Lecture Indexer (LI) from the [Milestone 1 proposal](proposal/CS6030_F26_ProjectProposal_LectureIndexer.pdf). Update the status table and decisions as work lands.

Last updated: 2026-10-13.

## Status

| Step | What | State |
|---|---|---|
| 1 | Move proposal into `docs/proposal/`, README, scaffold the tree | ✅ done (`c40b2b7`) |
| 2 | `db/migrations`, `services/` (li_common, ingest, search), Dockerfiles, docker-compose, Makefile | ✅ done (`73ed7d8`): 67 tests pass against Postgres 16 |
| 3 | Terraform: `infra/terraform/bootstrap`, then `envs/dev` | ⏭ next |
| 4 | `deploy/k8s` (Kustomize), GitHub workflows, `frontend/` | todo |
| 5 | Backup CronJob + Azure storage, monitoring module, security review doc | todo |

| Milestone | Due | Needs |
|---|---|---|
| M2 Prototype Review | Week 10 | Initial deployment, CI/CD pipeline, basic functionality (steps 3–4) |
| M3 Technical Review | Week 12 | Monitoring, security review, documentation (step 5) |
| Final Demonstration | Week 14 | Live demo, architecture talk, cost analysis, AI-usage reflection, lessons learned |

## Architecture

Per the proposal:

- **Frontend**: React + Vite + TypeScript SPA on Azure Static Web Apps; Google Sign-In (OAuth 2.0 / OIDC).
- **App tier**: two Flask services on GKE behind Cloud Load Balancing, **Ingest API** and **Search API**, each with its own HPA.
- **Data**: Cloud SQL for PostgreSQL (private IP), full-text search over timestamped caption segments.
- **Backups**: nightly K8s CronJob → encrypted `pg_dump` → Azure Blob Storage (immutable, cool tier), write-only credential in Secret Manager.
- **Platform**: Artifact Registry, Secret Manager + Workload Identity, Cloud Monitoring dashboard and alerts.
- **Delivery**: GitHub Actions with keyless OIDC to both clouds; Terraform for both providers.

## Decisions

| Decision | Why |
|---|---|
| **Flask** served by gunicorn (`--workers 2 --threads 4`), not FastAPI | Team choice. Each service is a `create_app()` factory plus one blueprint. What FastAPI would have given us lives in `li_common`: pydantic validation, JSON errors, a shared health blueprint. |
| **uv workspace** in `services/`, Python 3.12, `uv.lock` committed | One lockfile for both services and the shared package. |
| Images build from the **repo root** (`docker build -f services/ingest/Dockerfile .`) | The ingest image includes `db/migrations` for the migrate Job. |
| **Cloud SQL Auth Proxy** sidecar with `--auto-iam-authn` | The Cloud SQL Python Connector doesn't support psycopg. Services only see `DATABASE_URL` pointing at `127.0.0.1`. |
| **Numbered `.sql` migrations** run by `li-migrate`; no Alembic, no ORM | Small schema. Pending files apply in one transaction under an advisory lock. Runs as a K8s Job before each rollout. |
| Path prefixes **`/ingest/*`** and **`/search/*`** | One Ingress can route to both services. `/healthz` and `/readyz` stay unprefixed for probes. |
| **Professor role** from the `PROFESSOR_EMAILS` allowlist; everyone else is a student | Simple and auditable. Professors can only index videos from their own YouTube channel regardless. |
| **Ingestion runs inside the request** | The proposal has no queue. A lecture takes a few seconds; ingest's gunicorn timeout is 120 s. |
| **Dev auth** (`LI_DEV_AUTH=1`, `Authorization: Bearer dev:<email>`) | Local testing without Google. The services refuse to start with it inside Kubernetes. |
| Test files have **unique names** (e.g. `test_ingest_routes.py`) | pytest's default import mode needs unique basenames; `--import-mode=importlib` broke package imports. |

## Open items

- **YouTube scope.** The proposal says the professor's YouTube token is requested with a read-only scope, but `captions.list` and `captions.download` only accept `youtube.force-ssl`. The token is used for one request and never stored or logged. Correct this in the M3 security review.
- **Not yet verified:** `docker build` / `make dev-up`, calls to the real YouTube API, and real Google ID tokens. The tests mock YouTube and Google sign-in.
- **Workflow placeholders.** `.github/workflows/{ci,frontend-deploy,services-deploy,terraform}.yml` exist as empty files; fill them in at step 4.
- **Tooling.** Everyone needs [uv](https://docs.astral.sh/uv/getting-started/installation/) and Docker. `make test-db` runs the full suite against the compose Postgres on port 55432.

## Next: step 3, Terraform

```
infra/terraform/
├── bootstrap/                # apply once locally: GCS state bucket, GitHub OIDC
│                             #   (GCP Workload Identity Federation + Azure federated credential)
├── modules/
│   ├── gcp-network/          # VPC, private service access for Cloud SQL, Cloud NAT
│   ├── gke/                  # Autopilot cluster, Workload Identity
│   ├── cloudsql/             # Postgres 16, private IP, IAM DB users for the ingest/search/backup service accounts
│   ├── artifact-registry/
│   ├── secrets/              # Secret Manager entries + IAM bindings per Kubernetes service account
│   ├── monitoring/           # dashboard JSON, log-based metrics, alert policies (step 5)
│   ├── azure-static-web-app/
│   └── azure-backup-storage/ # cool tier, immutability policy, write-only SAS (step 5)
└── envs/dev/                 # main.tf wires modules; backend.tf → GCS; terraform.tfvars.example
```

**Cost rules:** GKE Autopilot with Spot Pods; the smallest Cloud SQL tier, stopped between work sessions; tear down when idle. Azure runs on the $100 Azure for Students credit; Static Web Apps uses the free tier. No AWS.

**Monitoring inputs.** The services already log these events as JSON, ready for log-based metrics:

| `event` | Fields |
|---|---|
| `http_request` | `service`, `method`, `route`, `status`, `latency_ms` |
| `youtube_api_call` | `method`, `status`, `quota_units` |
| `ingest_succeeded` / `ingest_failed` | `video_id`, `lecture_id`, `segments` / `reason` |

## Remaining steps

**Step 4.**
- `deploy/k8s`: namespace; per service a Deployment (with the Cloud SQL Proxy as a native sidecar), Service, HPA, and service account with Workload Identity; Ingress or Gateway with a managed certificate; the migrate Job; NetworkPolicy; `overlays/dev`.
- Workflows:
  - `ci.yml`: ruff, pytest with a Postgres service container, frontend lint and tests, `terraform fmt`/`validate`, `kustomize build`.
  - `services-deploy.yml`: build images to Artifact Registry, run the migrate Job, apply manifests.
  - `frontend-deploy.yml`: Static Web Apps deploy with PR previews.
  - `terraform.yml`: plan on PRs, apply on `main` with approval.
- `frontend/`: Google sign-in (ID token for everyone; a `youtube.force-ssl` access token for professors registering lectures), search page rendering `excerpt_html`, course management, lecture registration. The API contract is in [services/README.md](../services/README.md).

**Step 5.** `backup/` image and CronJob, the Azure backup storage module, the monitoring module, and `docs/milestones/m3-technical-review.md`.

## Verification target

- `make lint`, `make test-db`, `make dev-up`, then curl with `Bearer dev:<email>`.
- `terraform -chdir=infra/terraform/envs/dev validate && plan`; `kubectl kustomize deploy/k8s/overlays/dev`.
- CI green on a PR touching each top-level directory.
- End to end: sign in on the Static Web Apps URL, register a captioned video, search a spoken term, and the link opens at the right second.
