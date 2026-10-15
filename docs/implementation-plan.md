# Implementation plan

Living plan for building Lecture Indexer (LI) from the [Milestone 1 proposal](proposal/CS6030_F26_ProjectProposal_LectureIndexer.pdf). Update the status table and decisions as work lands.

Last updated: 2026-10-15.

## Status

| Step | What | State |
|---|---|---|
| 1 | Move proposal into `docs/proposal/`, README, scaffold the tree | ✅ done (`c40b2b7`) |
| 2 | `db/migrations`, `services/` (li_common, ingest, search), Dockerfiles, docker-compose, Makefile | ✅ done (`73ed7d8`): 67 tests pass against Postgres 16 |
| 3 | Terraform: `infra/terraform/bootstrap`, then `envs/prod` | ✅ written and validated (mocked `terraform test` passes); **not applied yet**, see [runbook](runbooks/bootstrap.md) |
| 4 | `deploy/k8s` (Kustomize), GitHub workflows, `frontend/` | ⏭ next |
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
| **Database privileges via group roles**: `li_ingest_role` (read/write), `li_search_role` (read, plus creating users at sign-in) | Cloud SQL IAM users start with no privileges. Migration `0002` creates the roles; the migrate Job logs in as the built-in `li_admin` user (password in Secret Manager) and runs `li-migrate --grant` (`LI_MIGRATE_GRANTS`) to add each IAM user to its role. |
| **One deployed environment, named `prod`** (`envs/prod`, `overlays/prod`, GitHub environment `prod`, `rg-li-prod`) | It's the only environment and the one demoed, so it is production. The `modules/` + `envs/<name>/` layout is kept, so a throwaway second environment would just be another folder. |
| **One Terraform state bucket** in GCS for both clouds; `bootstrap/` and `envs/prod` are separate roots | Bootstrap (CI identities) is applied once by a human; `envs/prod` can be destroyed and recreated freely. The bucket itself is created with `gcloud` because Terraform needs it first. |
| **Keyless CI**: GCP Workload Identity pool restricted to this repo; Azure user-assigned managed identities with federated credentials | No service account keys or client secrets anywhere. |
| **Powerful CI identities only in the `prod` GitHub environment** (`github-terraform`, `github-deploy`, `id-li-github`); **read-only identities for PRs** (`github-plan`, `id-li-github-plan`) | Bindings match the token's exact subject (`repo:…:environment:prod` vs `repo:…:pull_request`), so a workflow on a PR can't get write access. The `prod` environment requires an approval (no admin bypass; self-approval allowed) and only allows `main`. |
| **Pull requests into `main` are not enforced, and deploy self-approval is allowed** (for now) | Team choice. One person can push to `main` and approve their own deploy, so the `prod` approval is a deliberate confirmation step: check what changed on `main` (especially `.github/workflows/` and `infra/`) before approving. Tighten later with **Prevent self-review** or a PR ruleset on `main`; neither needs other changes. Once `ci.yml` exists, deploy jobs should require CI to pass. |
| **PR plans run `terraform plan -refresh=false -lock=false`** | Reading the Static Web App needs `listSecrets`, which Azure's Reader role lacks. PR plans show what the code change does; the full refresh happens in the plan before each apply. |
| **No secrets in Terraform state**: the `li_admin` password is an ephemeral `random_password` passed to write-only arguments (`password_wo`, `secret_data_wo`); rotate with `db_admin_password_version` | The PR plan identity can read state. Refreshes of write-only secrets also skip reading the value (checked in the provider source). Exception: azurerm stores the Static Web App deploy token in state. |
| **API hostname `<ip-with-dashes>.sslip.io`** on a reserved global IP | A Google-managed certificate needs a hostname; this avoids buying a domain. |
| **Private nodes and private-IP Cloud SQL**, Cloud NAT for outbound traffic | Nothing but the load balancer is reachable from the internet. NAT is needed for the backup upload to Azure Blob. |
| Terraform modules pass IAM members as **maps with static keys** | `for_each` keys must be known at plan time; member emails aren't until the service accounts exist. Caught by the mocked `terraform test`. |
| `li_common.logs`, not `li_common.logging` | A module named `logging` shadows the standard library when Python runs from inside the package folder. |

## Open items

- **YouTube scope.** The proposal says the professor's YouTube token is requested with a read-only scope, but `captions.list` and `captions.download` only accept `youtube.force-ssl`. The token is used for one request and never stored or logged. Correct this in the M3 security review.
- **Not yet verified:** `docker build` / `make dev-up`, calls to the real YouTube API, and real Google ID tokens. The tests mock YouTube and Google sign-in.
- **Infrastructure not applied.** Someone with Owner on both clouds follows [runbooks/bootstrap.md](runbooks/bootstrap.md): state bucket, `bootstrap/`, GitHub variables and the `prod` environment, the OAuth client (console only), then `envs/prod`. It needs `gcloud` and `az`. Provisioning starts billing (roughly $40–60/month while running; see the runbook's cost table), so apply close to when step 4 is ready to deploy, and destroy when idle.
- **Workflow placeholders.** `.github/workflows/{ci,frontend-deploy,services-deploy,terraform}.yml` exist as empty files; fill them in at step 4.
- **Tooling.** Everyone needs [uv](https://docs.astral.sh/uv/getting-started/installation/) and Docker. `make test-db` runs the full suite against the compose Postgres on port 55432.

## Done: step 3, Terraform

```
infra/terraform/
├── .terraform-version        # 1.16.4 (tfenv)
├── bootstrap/                # once, by hand: GitHub OIDC for GCP + Azure, CI service accounts
├── modules/
│   ├── gcp-network/          # VPC, pod/service ranges, private services access, Cloud NAT
│   ├── gke/                  # Autopilot, private nodes, least-privilege node SA, Secret Manager add-on
│   ├── cloudsql/             # Postgres 16 db-f1-micro, private IP, IAM auth, li_admin + IAM users
│   ├── artifact-registry/    # Docker repo with cleanup policies
│   ├── secrets/              # Secret Manager secrets with per-secret accessors
│   ├── azure-static-web-app/ # Free tier
│   ├── monitoring/           # step 5
│   └── azure-backup-storage/ # step 5
└── envs/prod/                 # wires the modules; identities.tf (Workload Identity); tests/ (mocked)
```

Checks: `terraform fmt -check -recursive`, `terraform validate` in both roots, `terraform -chdir=infra/terraform/envs/prod test`.

## Next: step 4

**Kubernetes (`deploy/k8s`).** Values come from `terraform output` in `envs/prod`:

| Manifest | Uses |
|---|---|
| Namespace `li` | must match `k8s_namespace` (Workload Identity bindings are scoped to it) |
| ServiceAccounts `ingest`, `search`, `migrate` | annotation `iam.gke.io/gcp-service-account` from `workload_service_accounts` |
| Deployments `ingest`, `search` | image from `image_repository`; Cloud SQL Auth Proxy as a native sidecar with `--auto-iam-authn --private-ip` on `cloudsql.connection_name`; `DATABASE_URL=host=127.0.0.1 dbname=li user=<iam user>`; `CORS_ORIGINS` = `frontend_url`; `GOOGLE_CLIENT_ID`; `PROFESSOR_EMAILS`; probes on `/healthz` and `/readyz`; Spot node selector |
| HPAs | CPU-based, min 1 |
| Migrate Job | ingest image, `li-migrate /app/migrations`; proxy **without** `--auto-iam-authn` (it logs in as `li_admin`); password mounted from Secret Manager `db-admin-password`; `LI_MIGRATE_GRANTS` from the `migrate_grants` output |
| Ingress + ManagedCertificate | static IP `li-api`, host `api_hostname`, paths `/ingest` → ingest, `/search` → search |
| NetworkPolicy | default deny ingress except from the load balancer to the APIs |

**Workflows.**
- `ci.yml`: ruff; pytest with a Postgres service container (`DATABASE_URL`); frontend lint and tests; `terraform fmt -check`, `validate`, `test`; `kustomize build`.
- `terraform.yml`: on PRs, `plan -refresh=false -lock=false` as `github-plan` / `id-li-github-plan` (`AZURE_PLAN_CLIENT_ID`, `ARM_RESOURCE_PROVIDER_REGISTRATIONS=none`), posted as a PR comment; on push to `main`, a full plan then apply in the `prod` environment as `github-terraform` / `id-li-github`.
- `services-deploy.yml`: in the `prod` environment, build both images, push to Artifact Registry, run the migrate Job, apply the overlay with the new image tags, as `github-deploy`.
- `frontend-deploy.yml`: in the `prod` environment, build, fetch the Static Web Apps deploy token with `id-li-github`, deploy. PR previews would need the token outside the environment, so skip them or accept that tradeoff.

**Frontend (`frontend/`).**
- Google sign-in: an ID token for everyone, plus a `youtube.force-ssl` access token for professors registering lectures.
- Pages: search (renders `excerpt_html`), course management, lecture registration.
- The API contract is in [services/README.md](../services/README.md).

**Monitoring inputs (for step 5).** The services already log these events as JSON, ready for log-based metrics:

| `event` | Fields |
|---|---|
| `http_request` | `service`, `method`, `route`, `status`, `latency_ms` |
| `youtube_api_call` | `method`, `status`, `quota_units` |
| `ingest_succeeded` / `ingest_failed` | `video_id`, `lecture_id`, `segments` / `reason` |

## Remaining: step 5

- `backup/` image and CronJob: `pg_dump` as `li_admin`, encrypted to a public key (the private key stays offline), uploaded with a write-only SAS from Secret Manager.
- `modules/azure-backup-storage`: cool tier, immutability policy, SAS.
- `modules/monitoring`: dashboard, log-based metrics, alert policies.
- `docs/milestones/m3-technical-review.md`, including the YouTube scope correction.

## Verification target

- `make lint`, `make test-db`, `make dev-up`, then curl with `Bearer dev:<email>`.
- `terraform -chdir=infra/terraform/envs/prod test` (no credentials), then `plan` against the real project; `kubectl kustomize deploy/k8s/overlays/prod`.
- CI green on a PR touching each top-level directory.
- End to end: sign in on the Static Web Apps URL, register a captioned video, search a spoken term, and the link opens at the right second.
