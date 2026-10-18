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
| 5. Google OAuth client | 🟡 client exists (from the YouTube test); needs the Cloud Run origin, after step 6 |
| 6. Apply `envs/prod` | 🟡 apply started 2026-10-18, by hand |
| 8. First deploy from GitHub Actions | todo: checklist below |

## Our environment

None of these are secrets.

| What | Value |
|---|---|
| GCP project | `lecture-indexer-511419` (number `294292796743`), region `us-central1` |
| Terraform state | `gs://lecture-indexer-511419-tfstate` (versioned, public access blocked) |
| Azure subscription | Azure for Students, `898a010f-f766-4657-b683-6fb3c7399a77`; resources in `northcentralus` |
| CI identities | GCP: `github-terraform`, `github-deploy`, `github-plan`. Azure: `id-li-github`, `id-li-github-plan` (resource group `rg-li-ci`) |
| GitHub `prod` environment | Deploys only from `main`; reviewers awojo, joshuajubenville, SisyphusRex; self-approval allowed; admin bypass on (team decision) |

## What we did

### Cost controls (before provisioning)

- `make cloud-pause` / `make cloud-resume` / `make cloud-status` (`scripts/cloud-power.sh`): scale the API pods to 0, delete the load balancer, stop Cloud SQL, and back. Idle cost drops to about $9/month, and the API hostname is kept. Runbook §7.
- Terraform ignores Cloud SQL's on/off state, so no apply restarts a paused database.
- CI runners are pinned to `ubuntu-24.04`.

### Deploy workflows

- `terraform.yml`, `services-deploy.yml` and `frontend-deploy.yml` deploy on push to `main` (filtered by path), after CI passes and someone approves in `prod`. They can also be run by hand. Runbook §8.
- While paused, the Terraform and services deploys skip with a warning instead of failing (`scripts/ci/check-paused.sh`). After `make cloud-resume`, re-run them.

### Bootstrap

1. Created the state bucket.
2. `terraform apply` in `bootstrap/` created everything on GCP: the Workload Identity pool, the three service accounts and their roles.
3. **Azure refused everything in `eastus2`** (`RequestDisallowedByAzure`). Our subscription only allows `canadacentral`, `mexicocentral`, `northcentralus`, `francecentral` and `swedencentral`. Moved Azure to `northcentralus` and applied again.
4. That apply was interrupted after it had created the two Azure identities but before it recorded them in state. Recovered by releasing the state lock, importing both identities, and applying the remaining 4 resources. A fresh plan now shows no changes.
5. Set the 11 GitHub variables from `terraform output github_variables`.

### Frontend moved to Cloud Run

Static Web Apps isn't offered in any region our subscription allows, so the frontend now runs as an nginx container on Cloud Run (`li-frontend`, scales to zero). Why, and what it changes: [ADR 0001](adr/0001-frontend-on-cloud-run.md). Azure now holds only the nightly backups (step 5 of the plan) and the identities that manage them.

### `envs/prod`

Plan: 52 resources to add (network, GKE Autopilot `li`, Cloud SQL `li-pg`, Artifact Registry `li`, Secret Manager, workload service accounts, Cloud Run `li-frontend`, global IP `li-api`, Azure `rg-li-prod`). Applied by hand on 2026-10-18. **Billing runs from here:** about $40–60/month while everything runs, about $9/month when paused.

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

### 5. Deploy: merge `development` into `main`

The merge changes `infra/`, the services and the frontend at once, so all three deploy workflows start. Each waits for CI, then for an approval in **Actions**. Approve them in this order:

1. **Terraform.** `envs/prod` is already applied, so its plan should show **no changes**. Read the plan in the run before it applies. This run is the first real test of the CI identities.
2. **Deploy services.** Builds the images, runs the migrate Job, rolls out ingest and search, and creates the load balancer. After it finishes, the Google-managed certificate takes **15–60 minutes**:
   ```sh
   gcloud container clusters get-credentials li --region us-central1
   kubectl -n li describe managedcertificate li-api   # wait for Status: Active
   ```
3. **Deploy frontend.** Builds the nginx image with the API hostname and client ID, then deploys it to Cloud Run. Until it runs, the Cloud Run URL shows Google's placeholder page.

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
