# Implementation plan

Living plan for building Lecture Indexer (LI) from the [Milestone 1 proposal](proposal/CS6030_F26_ProjectProposal_LectureIndexer.pdf). Update the status table and decisions as work lands.

Last updated: 2026-10-18.

## Status

| Step | What | State |
|---|---|---|
| 1 | Move proposal into `docs/proposal/`, README, scaffold the tree | ✅ done (`c40b2b7`) |
| 2 | `db/migrations`, `services/` (li_common, ingest, search), Dockerfiles, docker-compose, Makefile | ✅ done (`73ed7d8`): 67 tests pass against Postgres 16 |
| 3 | Terraform: `infra/terraform/bootstrap`, then `envs/prod` | 🟡 written and validated (mocked `terraform test` passes). Bootstrap applied 2026-10-18 (Azure in `northcentralus` after the region policy refused `eastus2`); GitHub variables and the `prod` environment set. `envs/prod` not applied yet. See [runbook](runbooks/bootstrap.md) |
| 4 | `deploy/k8s` (Kustomize), GitHub workflows, `frontend/` | 🟡 everything written: `ci.yml`, manifests (validated), frontend (tested), deploy workflows (linted, not run yet). Real Google/YouTube test passed 2026-10-18. Next: the first deploy ([first-deployment.md](first-deployment.md)) |
| 5 | Backup CronJob + Azure storage, monitoring module, security review doc | todo |

| Milestone | Due | Needs |
|---|---|---|
| M2 Prototype Review | Week 10 | Initial deployment, CI/CD pipeline, basic functionality (steps 3–4) |
| M3 Technical Review | Week 12 | Monitoring, security review, documentation (step 5) |
| Final Demonstration | Week 14 | Live demo, architecture talk, cost analysis, AI-usage reflection, lessons learned |

## Architecture

Per the proposal:

- **Frontend**: React + Vite + TypeScript SPA served by nginx on **Cloud Run** (the proposal said Azure Static Web Apps; see [ADR 0001](adr/0001-frontend-on-cloud-run.md)); Google Sign-In (OAuth 2.0 / OIDC).
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
| **Powerful CI identities only in the `prod` GitHub environment** (`github-terraform`, `github-deploy`, `id-li-github`); **read-only identities for PRs** (`github-plan`, `id-li-github-plan`) | Bindings match the token's exact subject (`repo:…:environment:prod` vs `repo:…:pull_request`), so a workflow on a PR can't get write access. The `prod` environment requires an approval (self-approval allowed; repository admins may bypass it, a team decision of 2026-10-18) and only allows `main`. |
| **Pull requests into `main` are not enforced, and deploy self-approval is allowed** (for now) | Team choice. One person can push to `main` and approve their own deploy, so the `prod` approval is a deliberate confirmation step: check what changed on `main` (especially `.github/workflows/` and `infra/`) before approving. Tighten later with **Prevent self-review** or a PR ruleset on `main`; neither needs other changes. Deploys wait for CI to pass on the same commit before asking for approval. |
| **PR plans run `terraform plan -refresh=false -lock=false`** | The plan identities are read-only (GCP Viewer, Azure Reader). PR plans show what the code change does; the full refresh happens in the plan before each apply. Originally required because Reader couldn't refresh the Static Web App; kept after the move to Cloud Run. |
| **No secrets in Terraform state**: the `li_admin` password is an ephemeral `random_password` passed to write-only arguments (`password_wo`, `secret_data_wo`); rotate with `db_admin_password_version` | The PR plan identity can read state. Refreshes of write-only secrets also skip reading the value (checked in the provider source). No deploy tokens exist either: CI uses short-lived Workload Identity credentials. |
| **API hostname `<ip-with-dashes>.sslip.io`** on a reserved global IP | A Google-managed certificate needs a hostname; this avoids buying a domain. |
| **Private nodes and private-IP Cloud SQL**, Cloud NAT for outbound traffic | Nothing but the load balancer is reachable from the internet. NAT is needed for the backup upload to Azure Blob. |
| Terraform modules pass IAM members as **maps with static keys** | `for_each` keys must be known at plan time; member emails aren't until the service accounts exist. Caught by the mocked `terraform test`. |
| **Kubernetes values in one file**: `deploy/k8s/overlays/prod/values/values.env` → ConfigMap `li-config`, plus kustomize `replacements` for annotations, the hostname, and the secret name | Pods read values through `configMapKeyRef` and `$(VAR)` expansion; filling in production values after `terraform apply` is a one-file change. |
| **Cloud SQL Auth Proxy as a native sidecar** (`initContainers` with `restartPolicy: Always`) | Starts before the app and stops after it; in the migrate Job it exits on its own, so the Job can complete. |
| **Migrate Job in its own kustomization** (`deploy/k8s/migrate`, overlay `overlays/prod/migrate`) | The deploy workflow runs it to completion before rolling out the app. It reads the `li_admin` password from a Secret Manager-mounted file into `PGPASSWORD`, so the password is never in a URL or argument. |
| **Spot pods, read-only root filesystems, non-root, all capabilities dropped** | Cost and least privilege; gunicorn gets an in-memory `/tmp`. |
| **Frontend: React 19, Vite 8, React Router 8, TypeScript 6.0** | Current releases; TypeScript stays below 6.1 because typescript-eslint doesn't support newer yet. |
| **The Vite dev server proxies `/ingest` and `/search`** to the local APIs | The app uses the same paths locally and in production (`VITE_API_BASE` = the API host). |
| **Search excerpts are rendered without `innerHTML`**: the client splits `excerpt_html` on `<mark>` and emits text nodes | Defense in depth on top of the server's escaping. |
| **Professor detection**: the frontend calls `GET /ingest/courses`; 403 means student | No extra endpoint needed; roles stay server-side. |
| **The YouTube access token stays in browser memory** until shortly before it expires | One consent popup per session, never stored. |
| **Only YouTube's auto-generated (ASR) captions**, fetched with `captions.download`; tracks the creator uploaded are ignored, and users never upload caption files to us | One caption source, one format (WebVTT). A video without an ASR track fails with `422 no_captions`. |
| **Pause between test sessions instead of destroying**: `make cloud-pause` scales the pods to 0, deletes the Ingress (load balancer), and stops Cloud SQL; Terraform ignores `activation_policy` | Idle cost drops to ~$9/month (SQL storage, reserved IP), and the reserved IP, and with it the API hostname, survives. Destroying changes the hostname, which means editing `values.env`, the CSP and the OAuth origins. Ignoring the on/off state stops a CI apply from restarting a paused database. |
| **Workflows run on `ubuntu-24.04`**, not `ubuntu-latest` | `ubuntu-latest` moves to Ubuntu 26 from 2026-10-19; pinning keeps the runner image from changing under CI while the deploy workflows are written. Use the same label in new workflows, and upgrade all of them together on purpose. |
| **Deploy on push to `main`, with a pause check**: path filters pick which of the three deploy workflows run; each waits for CI, then for `prod` approval | Merges deploy without extra steps. While paused (`make cloud-pause`), `terraform.yml` and `services-deploy.yml` skip with a warning instead of failing on the stopped database or re-creating the load balancer (`scripts/ci/check-paused.sh`); re-run them after `make cloud-resume`. The frontend deploy has no check: it's free and harmless while paused. `github-deploy` gets Cloud SQL Viewer for the check. |
| **Frontend on Cloud Run, not Azure Static Web Apps** ([ADR 0001](adr/0001-frontend-on-cloud-run.md)): nginx image (`frontend/Dockerfile`), service `li-frontend` (public, 0–2 instances), deployed with `gcloud run deploy` | The Azure for Students region policy allows none of the regions Static Web Apps is offered in. Cloud Run is a listed frontend host, scales to zero (~$0), and reuses Docker, Artifact Registry and the `github-deploy` identity, which gets `run.developer` on that one service only. nginx sets the CSP; its `connect-src` follows `VITE_API_BASE` at build time. Terraform ignores the deployed image. |
| **Azure resources in `northcentralus`** | The subscription may only deploy to `canadacentral`, `mexicocentral`, `northcentralus`, `francecentral` and `swedencentral`; North Central US is closest to `us-central1`. |
| **The frontend build reads `API_HOSTNAME` and `GOOGLE_CLIENT_ID` from `values.env`** | One file to fill in after `terraform apply`, for the services and the frontend; no extra GitHub variables. |
| **Image tags are the commit SHA**, set with `kustomize edit set image` in the deploy job and never committed | Each rollout names exactly what's running. `make cloud-resume` therefore re-applies only the Ingress, not the overlay with its placeholder tags. |
| `li_common.logs`, not `li_common.logging` | A module named `logging` shadows the standard library when Python runs from inside the package folder. |

## Open items

- **YouTube scope.** The proposal says the professor's YouTube token is requested with a read-only scope, but `captions.list` and `captions.download` only accept `youtube.force-ssl`. The token is used for one request and never stored or logged. Correct this in the M3 security review.
- **Not yet verified:** calls to the real YouTube API and real Google ID tokens (tests mock both); the next step below covers them. `docker build` and the compose stack are verified by the `compose` job in `ci.yml` on the first push.
- **Infrastructure not applied.** Someone with Owner on both clouds follows [runbooks/bootstrap.md](runbooks/bootstrap.md): state bucket, `bootstrap/`, GitHub variables and the `prod` environment, the OAuth client (console only), then `envs/prod`. It needs `gcloud` and `az`. Provisioning starts billing (roughly $40–60/month while running; see the runbook's cost table), so apply close to when step 4 is ready to deploy. Between test sessions, `make cloud-pause` / `make cloud-resume` cut idle cost to ~$9/month without changing the API hostname; destroy when idle for longer (runbook §7).
- **Deploy workflows written but never run.** `terraform.yml`, `services-deploy.yml` and `frontend-deploy.yml` pass `actionlint`, but nothing in them has touched a real cloud yet: they need bootstrap applied (GitHub variables, the `prod` environment). Until then a push to `main` that touches their paths starts a run that fails at sign-in. Expect fixes during the first deploy ([runbook §8](runbooks/bootstrap.md#8-deploy-from-github-actions)).
- **Tooling.** Required tools and install steps for Linux and WSL2 are in [local-development.md](local-development.md); `make doctor` checks them.

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
│   ├── cloud-run-frontend/   # nginx SPA on Cloud Run, public, deployers scoped to the service
│   ├── monitoring/           # step 5
│   └── azure-backup-storage/ # step 5
└── envs/prod/                # wires the modules; identities.tf (Workload Identity); tests/ (mocked)
```

Checks: `terraform fmt -check -recursive`, `terraform validate` in both roots, `terraform -chdir=infra/terraform/envs/prod test`.

## Step 4 so far: everything that doesn't need the cloud

**CI (`.github/workflows/ci.yml`)**, on pushes to `main`/`development` and on PRs, with no cloud credentials:

| Job | Checks |
|---|---|
| `python` | `make lint`; `make test` against a Postgres service container (all DB tests run) |
| `compose` | `docker compose up --build`, migrations exit 0, then `scripts/smoke-test.sh` (sign-in, roles, course creation, search) |
| `terraform` | `fmt -check`, `validate` in both roots, mocked `terraform test` |
| `k8s` | `make k8s-check`: `kustomize build` + `kubeconform -strict` on both overlays |
| `frontend` | `npm ci`, lint, vitest, production build |
| `frontend-image` | `scripts/test-frontend-image.sh`: builds the nginx image, then checks the app, SPA fallback, 404s, `/healthz`, and the CSP and cache headers |

**Kubernetes (`deploy/k8s`)**

```
deploy/k8s/
├── base/                 # namespace; ingest/ and search/ (ServiceAccount, Deployment, Service + BackendConfig, HPA);
│                         #   Ingress + ManagedCertificate + FrontendConfig; NetworkPolicies
├── migrate/              # ServiceAccount, SecretProviderClass (db-admin-password), Job
└── overlays/prod/        # app overlay (images); migrate/ overlay; values/ component (values.env → li-config)
```

Fill `overlays/prod/values/values.env` from `terraform output` (each line names its output) once the infrastructure exists. The deploy workflow sets image tags with `kustomize edit set image`.

**Frontend (`frontend/`)**: React app with Google sign-in (or dev sign-in with `VITE_DEV_AUTH=1`), course list, course search with timestamped links and highlighted excerpts, and a professor page to create courses and register or remove lectures. Run it with `make frontend-dev` against the local APIs. 16 vitest tests cover the API client, excerpt rendering (including escaped markup staying text), search, and lecture registration.

## Next: real Google/YouTube test (free, before deploying)

The automated tests mock Google sign-in and the YouTube API. This test runs the local stack against both for real. It takes about 20 minutes and needs no billing account.

**You need:**
- A Google account whose YouTube channel has a video with **auto-generated** captions. YouTube creates them some time after upload. YouTube Studio → Subtitles shows an "English (automatic)" track once they exist. An unlisted video works.
- Optionally, a second video of yours with only uploaded captions, and the URL of any video you don't own.
- The local setup from [local-development.md](local-development.md) working (`make dev-up`, `make frontend-dev`).

### 1. Google Cloud Console (once)

Do this in the GCP project Terraform will use. Any project works, but this one reuses the OAuth client in production; Terraform can't create the client (runbook step 5).

1. **APIs & Services → Library**: enable **YouTube Data API v3**. API calls count against this project's free daily quota.
2. **OAuth consent screen**:
   - User type **External**, publishing status **Testing**.
   - Scopes: `openid`, `email`, `profile`, `https://www.googleapis.com/auth/youtube.force-ssl`.
   - **Test users**: add every tester's Google account. Others can't sign in while the app is in Testing.
3. **Credentials → Create credentials → OAuth client ID**:
   - Type **Web application**.
   - Authorized JavaScript origin `http://localhost:5173`. No redirect URI is needed.
   - Copy the client ID. It isn't a secret.

### 2. Start the APIs with real Google auth

`docker-compose.yml` hardcodes dev auth. The override `docker-compose.google.yml` (in the repo root) turns it off for `migrate`, `ingest` and `search`, and reads two values from `.env`. Create `.env` in the repo root; it's git-ignored, and Compose reads it itself, so the values also work under `sudo`:

```
GOOGLE_CLIENT_ID=<id>.apps.googleusercontent.com
PROFESSOR_EMAILS=<your Google email>
```

Then start the stack (prefix `sudo` if your user isn't in the `docker` group):

```sh
make dev-down                       # stop a dev-auth stack if one is running
docker compose -f docker-compose.yml -f docker-compose.google.yml up --build -d
docker compose logs -f ingest       # leave running in a second terminal
```

Don't run `make smoke` against this stack. It signs in with `dev:` tokens, which are now rejected.

### 3. Start the frontend with Google sign-in

In `frontend/.env.local`:

```
VITE_DEV_AUTH=0
VITE_GOOGLE_CLIENT_ID=<same id>
VITE_API_BASE=
```

Then run `make frontend-dev` and open http://localhost:5173. Vite reads `.env.local` only at startup, so restart it after editing.

### 4. Test cases

| # | Do | Expect |
|---|---|---|
| 1 | Sign in with Google | Signed in. Because the app is in Testing, Google shows an "unverified app" warning; continue. |
| 2 | Open **Manage** | The page loads. A student view means your email isn't in `PROFESSOR_EMAILS`. |
| 3 | Create a course, register your video with auto-captions; grant the YouTube permission when asked | Lecture `indexed` with a segment count; the log shows `youtube_api_call` lines and `ingest_succeeded` |
| 4 | As any user, search the course for a word you say in the video | A hit with a highlighted excerpt; the link opens YouTube within a few seconds before the word |
| 5 | Register the same video again | Still `indexed`, same segment count (re-index, no duplicates) |
| 6 | Register a video you don't own | "You can only register videos from your own YouTube channel" (`403 not_video_owner`) |
| 7 | (Optional) Register your video with only uploaded captions | Lecture `failed`: "The video has no auto-generated captions" (`422 no_captions`) |
| 8 | Delete a lecture | It disappears, and search no longer finds it |

To see what was stored, run:

```sh
docker compose exec db psql -U li -d li -c \
  "select start_ms/1000 as sec, left(text, 80) from segments order by start_ms limit 15;"
```

The text should read as clean running speech: no repeated phrases, no `<c>` or timestamp tags. The times should match the video.

### 5. If something fails

| Symptom | Likely cause |
|---|---|
| Google popup: `Error 400: redirect_uri_mismatch` or "origin not allowed" | `http://localhost:5173` is missing from the OAuth client's JavaScript origins. Changes can take a few minutes to apply. |
| `Error 403: access_denied` at sign-in | Your account isn't a test user on the consent screen |
| `401 Invalid or expired ID token` | `GOOGLE_CLIENT_ID` in `.env` doesn't match `VITE_GOOGLE_CLIENT_ID`, or the APIs weren't recreated after you edited `.env` (run `up -d` again) |
| `400 youtube_token_invalid` | The YouTube permission was declined, or the scope isn't on the consent screen |
| `403 not_video_owner` on your own video | The account owns the video but `captions.download` refused the auto-generated track. See "Record" below. If the account has several channels (brand accounts), pick the video's channel when you sign in. |
| `502 youtube_error` mentioning the API | YouTube Data API v3 isn't enabled in the project |
| `422 no_captions` on a video that should have auto-captions | The ASR track isn't ready yet, or it's disabled for the video in YouTube Studio |

### 6. Record the results

Write a short "Results (date)" note under this section covering:

- Which cases passed, with the video's length and its segment count.
- **Whether `captions.download` serves the auto-generated track for the owner's video.** If it doesn't (`403`), map that 403 to its own error code instead of `not_video_owner`, and rethink caption fetching before deploying.
- **Whether the real WebVTT matches the fixture** `services/ingest/tests/fixtures/lecture4.vtt`: word-timing tags, rolling repeated lines, the `" "` line after each timing. The fixture is modeled on YouTube's usual ASR format, not on a real `captions.download` response. If they differ, replace the fixture with a trimmed real download and update `test_captions.py`.
- How far deep links land from the spoken word, on average.

### Results (2026-10-18)

Run log: [real-youtube-test.md](real-youtube-test.md). Video: "Welcome to Michigan" (owner's channel, auto-generated captions only).

- **All cases passed** except 7 (no video with only uploaded captions; covered by unit and route tests): Google sign-in, professor and student roles, registration (37 segments, 650 ms), search with deep links, re-registering without duplicates, rejecting a video from another channel (`403`, nothing written), and delete.
- **`captions.download` serves the auto-generated track** to the video's owner with `youtube.force-ssl`. The ASR-only design works.
- **Real ASR WebVTT parses cleanly**: no tags or rolling repeats in the stored text. The raw VTT wasn't captured, so `lecture4.vtt` is still modeled rather than copied.
- **Deep links land up to ~20 s early** (~10 s in the test): a link opens at the start of its window.
- **Quota**: one registration costs 252 units (1 + 1 + 50 + 200), so the default 10,000 units a day allow ~39 registrations.
- **Fixed during the test**: gunicorn 26's control socket failed in the container (`bcd1e71`).

Follow-ups:
- ~~Strip ASR sound tags such as `[Music]`~~ Done: `captions.py` drops `[...]` tags, and cues left empty are skipped. Lectures indexed before this keep the tags until they are re-registered.
- Optional: shorter windows (`max_ms` in `merge_segments`) for tighter deep links.
- M3 security review: the consent screen tells professors the app can "see, edit, and permanently delete" their YouTube videos; explain that only GET calls are made and the token is never stored.

### Finish

To finish, run `docker compose -f docker-compose.yml -f docker-compose.google.yml down`, then set `VITE_DEV_AUTH=1` again to return to dev sign-in. You can keep `.env` and the override file for next time.

## After that: deploy (needs billing)

The deploy workflows are written ([runbook §8](runbooks/bootstrap.md#8-deploy-from-github-actions) has triggers and the first-deploy steps). What remains: apply bootstrap and `envs/prod` ([runbook](runbooks/bootstrap.md)), fill `values.env`, push to `main`, and fix what the first real run turns up. As designed:
- `terraform.yml`: on PRs, `plan -refresh=false -lock=false` as `github-plan` / `id-li-github-plan` (`AZURE_PLAN_CLIENT_ID`, `ARM_RESOURCE_PROVIDER_REGISTRATIONS=none`), posted as a PR comment; on push to `main`, a full plan then apply in the `prod` environment as `github-terraform` / `id-li-github`.
- `services-deploy.yml`: in the `prod` environment, as `github-deploy`: build both images, push to Artifact Registry, create the namespace, run the migrate overlay and wait for the Job, then apply the app overlay with the new image tags and wait for the rollouts.
- `frontend-deploy.yml`: in the `prod` environment, as `github-deploy`: build the nginx image with `VITE_API_BASE=https://<api_hostname>` and `VITE_GOOGLE_CLIENT_ID`, push it, `gcloud run deploy li-frontend`. Also add the Cloud Run URL as an authorized origin on the OAuth client.

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

- `make lint`, `make test-db`, `make dev-up`, `make smoke`; `make frontend-test`; `make k8s-check`.
- `terraform -chdir=infra/terraform/envs/prod test` (no credentials), then `plan` against the real project; `make k8s-check`.
- CI green on a PR touching each top-level directory.
- End to end: sign in on the Cloud Run URL, register a captioned video, search a spoken term, and the link opens at the right second.
