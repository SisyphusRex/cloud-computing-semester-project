# First deployment

What we've done to get Lecture Indexer into production, and the checklist for the first deploy. The general procedure is in the [bootstrap runbook](runbooks/bootstrap.md); this page records what actually happened in our project, with the real names, and what's left.

Last updated: 2026-10-18.

## Where we are

| Runbook step | State |
|---|---|
| 1. Sign in, pick the project | ✅ done |
| 2. Terraform state bucket | ✅ done |
| 3. Apply `bootstrap/` (CI identities) | ✅ done, after a region fix (below) |
| 4. GitHub variables and `prod` environment | ✅ done |
| 5. Google OAuth client | 🟡 client exists (from the YouTube test); needs the Cloud Run origin (checklist step 3) |
| 6. Apply `envs/prod` | ✅ applied 2026-10-18, by hand |
| 8. First deploy from GitHub Actions | 🟡 `values.env` filled in; first merge rejected (we redesigned the workflows); next: bootstrap `prod-plan`, OAuth origin, then merge to `main` |

## Our environment

None of these are secrets.

| What | Value |
|---|---|
| GCP project | `lecture-indexer-511419` (number `294292796743`), region `us-central1` |
| Terraform state | `gs://lecture-indexer-511419-tfstate` (versioned, public access blocked) |
| Azure subscription | Azure for Students, `898a010f-f766-4657-b683-6fb3c7399a77`; resources in `northcentralus` |
| CI identities | GCP: `github-terraform`, `github-deploy`, `github-plan`. Azure: `id-li-github`, `id-li-github-plan` (resource group `rg-li-ci`) |
| API | `https://34-128-137-19.sslip.io` (global IP `34.128.137.19`) |
| Frontend | `https://li-frontend-byshtpdfha-uc.a.run.app` (Cloud Run `li-frontend`) |
| GitHub `prod` environment | Deploys only from `main`; reviewers awojo, joshuajubenville, SisyphusRex; self-approval allowed; admin bypass on (team decision) |

## What we did

### Cost controls (before provisioning)

- `make cloud-pause` / `make cloud-resume` / `make cloud-status` (`scripts/cloud-power.sh`): scale the API pods to 0, delete the load balancer, stop Cloud SQL, and back. Idle cost drops to about $9/month, and the API hostname is kept. Runbook §7.
- Terraform ignores Cloud SQL's on/off state, so no apply restarts a paused database.
- CI runners are pinned to `ubuntu-24.04`.

### Deploy workflows

- First version: three workflows, one per part, each with its own approval. The first merge to `main` showed the problem: three approvals in no fixed order, and the Terraform plan only visible after approving. We rejected those runs and moved `main` back.
- Now: one `release.yml` per merge. It shows a review sheet and the real Terraform plan, then one approval releases everything in order, rolls back automatically on a crash, and tags the commit `prod-YYYY-MM-DD.N`. `rollback.yml` returns to an earlier tag. See [release-process.md](release-process.md).
- While paused, the release stops before asking for approval (`scripts/ci/check-paused.sh`).

### Bootstrap

1. Created the state bucket.
2. `terraform apply` in `bootstrap/` created everything on GCP: the Workload Identity pool, the three service accounts and their roles.
3. **Azure refused everything in `eastus2`** (`RequestDisallowedByAzure`). Our subscription only allows `canadacentral`, `mexicocentral`, `northcentralus`, `francecentral` and `swedencentral`. Moved Azure to `northcentralus` and applied again.
4. That apply was interrupted after it had created the two Azure identities but before it recorded them in state. Recovered by releasing the state lock, importing both identities, and applying the remaining 4 resources. A fresh plan now shows no changes.
5. Set the 11 GitHub variables from `terraform output github_variables`.

### Frontend moved to Cloud Run

Static Web Apps isn't offered in any region our subscription allows, so the frontend now runs as an nginx container on Cloud Run (`li-frontend`, scales to zero). Why, and what it changes: [ADR 0001](architecture_decision_records/0001-frontend-on-cloud-run.md). Azure now holds only the nightly backups (step 5 of the plan) and the identities that manage them.

### `envs/prod`

Plan: 52 resources to add (network, GKE Autopilot `li`, Cloud SQL `li-pg`, Artifact Registry `li`, Secret Manager, workload service accounts, Cloud Run `li-frontend`, global IP `li-api`, Azure `rg-li-prod`). Applied by hand on 2026-10-18. GKE took 7m38s and Cloud SQL 13m4s. The first run failed on the Artifact Registry repository, because the module didn't wait for its API (enabled in the same run) to be ready; we added the missing `depends_on`, and a second apply created the last 3 resources. A fresh plan shows no changes. **Billing runs from here:** about $40–60/month while everything runs, about $9/month when paused.

## Checklist: first deploy

Work through these in order. Steps 1–4 happen on `development`; step 5 is the deploy itself.

### 1. Confirm the infrastructure

```sh
terraform -chdir=infra/terraform/envs/prod output
```

You need `api_hostname`, `frontend_url`, `cloudsql`, `workload_service_accounts` and `migrate_grants`.

### 2. Fill in `values.env`

Edit `deploy/k8s/overlays/prod/values/values.env`. Each line's comment names its output:

| Line | Value |
|---|---|
| `GOOGLE_CLIENT_ID` | The OAuth client ID from the YouTube test (same as `GOOGLE_CLIENT_ID` in your local `.env`) |
| `PROFESSOR_EMAILS` | Comma-separated Google accounts that get the professor role |
| `CORS_ORIGINS` | `frontend_url` |
| `CLOUDSQL_CONNECTION_NAME` | `cloudsql.connection_name` |
| `INGEST_DB_USER`, `SEARCH_DB_USER` | The service account emails without `.gserviceaccount.com` |
| `MIGRATE_GRANTS` | `migrate_grants` |
| `INGEST_GSA`, `SEARCH_GSA`, `MIGRATE_GSA` | `workload_service_accounts` |
| `API_HOSTNAME` | `api_hostname` |
| `DB_ADMIN_SECRET_VERSION` | `cloudsql.admin_password_secret` + `/versions/latest` |

No `PROJECT_ID`, `REPLACE_ME` or `0-0-0-0` may remain: both deploys refuse to run otherwise. Check the result with `make k8s-check` (or let CI do it).

### 3. Update the OAuth client

In the GCP console, **APIs & Services**:

- **Credentials → the web client → Authorized JavaScript origins:** add `frontend_url` (`https://li-frontend-….run.app`). Keep `http://localhost:5173`.
- **OAuth consent screen → Test users:** every teammate and demo account. The app stays in Testing.

### 4. Commit and check CI

Commit `values.env` on `development`, push, and wait for CI to pass.

### 5. Release: merge `development` into `main`

Before merging, `make release-diff` shows what will ship. After the push, one **Release** run starts. Its `review` and `plan` jobs run first; then it waits for approval in **Actions**. Go through [release-process.md](release-process.md#before-you-approve), then approve once:

- **Terraform plan:** `envs/prod` is already applied, so the plan should say **no changes**, and the apply step is skipped. This plan job is also the first real test of the CI identities.
- **The release job:** a backup (migrations `0001`/`0002` are new), the images, the migrations, ingest and search, the load balancer, and the frontend. On this first release the API check only warns, because the Google-managed certificate takes **15–60 minutes**:
  ```sh
  gcloud container clusters get-credentials li --region us-central1
  kubectl -n li describe managedcertificate li-api   # wait for Status: Active
  ```
- **Tag:** `prod-2026-10-18.1` and a GitHub Release appear when it succeeds.

Optionally, test the rollback once: `gh workflow run rollback.yml --ref main -f tag=prod-2026-10-18.1`. It redeploys the same release and should change nothing.

### 6. Verify end to end

- Once the certificate is active, `curl -i https://<api_hostname>/search/courses` returns `401` (the request reached the Search API, which needs a sign-in), and `curl <frontend_url>/healthz` returns `ok`.
- On the Cloud Run URL: sign in with Google, open **Manage** as a professor, register a video with auto-generated captions, search a spoken word as a student, and check that the link opens YouTube at the right moment.
- Record the results here, and update the status table in [implementation-plan.md](implementation-plan.md).

### 7. Pause when done

```sh
make cloud-pause    # and make cloud-resume next time
```

## Expect fixes on the first run

None of the deploy workflows has run against the real clouds yet. Likely trouble spots:

- **Cloud Run permissions.** `github-deploy` has `run.developer` on the `li-frontend` service only. If `gcloud run deploy` needs a project-level permission, the frontend deploy fails with a 403; grant the missing role in `modules/cloud-run-frontend`.
- **Terraform while paused.** The apply workflow skips while Cloud SQL is stopped, because refreshing database users probably fails then. That assumption hasn't been tested yet.
- **The certificate.** `sslip.io` hostnames should work with Google-managed certificates, but provisioning is slow, and `curl` shows certificate errors until it's done.
- **Google sign-in from `run.app`.** The origin must be added exactly, including `https://` and no trailing slash. Changes can take a few minutes to apply.
- **YouTube quota.** One registration costs 252 units of the 10,000 a day (about 39 registrations).
