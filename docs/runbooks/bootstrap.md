# Bootstrap and provision the cloud infrastructure

One person does steps 1–5 once. After that, CI runs Terraform (step 4 of the [implementation plan](../implementation-plan.md)). Steps 6–7 apply to anyone who provisions or tears down the production environment, and step 8 describes how GitHub Actions deploys.

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) 1.16.4. With [tfenv](https://github.com/tfutils/tfenv), `infra/terraform/.terraform-version` selects it automatically.
- [gcloud CLI](https://cloud.google.com/sdk/docs/install) and [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli).
- A GCP project with billing (GCP credits), and the Azure for Students subscription. That subscription may only deploy to `canadacentral`, `mexicocentral`, `northcentralus`, `francecentral` and `swedencentral` (policy `sys.regionrestriction`); our Azure resources use `northcentralus`. It's why the frontend runs on Cloud Run: [ADR 0001](../architecture_decision_records/0001-frontend-on-cloud-run.md).
- Owner on both. You need Owner, or Owner plus User Access Administrator in Azure, to create the CI identities and their role assignments.

## 1. Sign in and pick the project

```sh
gcloud auth login
gcloud auth application-default login        # credentials Terraform uses
gcloud config set project <project-id>

az login
az account show --query id -o tsv            # subscription ID for the tfvars files
```

## 2. Create the Terraform state bucket

Terraform state for both clouds lives in one GCS bucket. It's created by hand because Terraform needs it before it can run.

```sh
PROJECT=$(gcloud config get-value project)
gcloud storage buckets create gs://$PROJECT-tfstate \
  --location=us-central1 --uniform-bucket-level-access --public-access-prevention
gcloud storage buckets update gs://$PROJECT-tfstate --versioning
```

## 3. Apply `bootstrap/`

This creates keyless GitHub Actions access to both clouds. A Workload Identity pool only accepts this repository's tokens, and which identity a job gets depends on how the job runs:

| Job runs… | GCP service account | Azure identity | Can |
|---|---|---|---|
| in the `prod` GitHub environment | `github-terraform` | `id-li-github` (Contributor) | apply Terraform |
| in the `prod` GitHub environment | `github-deploy` | — | push images, deploy to GKE, read Cloud SQL's state (the pause check) |
| on a pull request | `github-plan` (Viewer, read state) | `id-li-github-plan` (Reader) | `terraform plan -refresh=false -lock=false` |

Nothing else, including jobs on branch pushes outside the `prod` environment, can get credentials.

```sh
cd infra/terraform/bootstrap
cp terraform.tfvars.example terraform.tfvars   # fill in real IDs; git-ignored
terraform init -backend-config="bucket=$PROJECT-tfstate"
terraform apply
terraform output github_variables
```

If Azure reports an unregistered resource provider, register it and re-apply: `az provider register --namespace Microsoft.ManagedIdentity`. A `RequestDisallowedByAzure` error means a resource is in a region the subscription doesn't allow (see Prerequisites).

## 4. Configure GitHub

In the repository settings:

1. **Variables** (Settings → Secrets and variables → Actions → Variables): add each entry from `github_variables`. None of them are secrets.
2. **Environment** (Settings → Environments): create `prod`. It's the only way into the powerful identities, so protect it:
   - **Required reviewers:** add the teammates, so every apply and deploy waits for an explicit approval. **Prevent self-review** stays off (team decision, 2026-10-15): whoever triggered a deploy may approve it.
   - **Allow administrators to bypass configured protection rules** stays on (team decision, 2026-10-18). A repository admin can then deploy without an approval, so the approval binds everyone else; turn it off to make it binding for admins too.
   - **Deployment branches and tags:** **Selected branches and tags** → `main` only.

   Without these, any workflow that names `environment: prod` gets admin-level credentials.

   **Pull requests into `main` are not enforced** (team decision, 2026-10-15). Collaborators can push straight to `main`, so the branch limit only keeps feature branches from deploying. Together with self-approval, one person can push to `main` and approve their own deploy; the approval is a deliberate confirmation step, not a second person's review. Before approving, look at what changed on `main` since the last deploy, especially `.github/workflows/` and `infra/`, because the workflow that runs is the one on `main` at that moment.

   To tighten this later, turn off the admin bypass, check **Prevent self-review** (a second person approves every deploy) or add a branch ruleset on `main` requiring a pull request with one approval and an empty bypass list. Neither needs other changes.

## 5. Create the Google OAuth client (console only)

Terraform can't create OAuth clients for external users, so do this in the console under **APIs & Services**:

1. **OAuth consent screen**:
   - User type **External**, publishing status **Testing**.
   - Scopes: `openid`, `email`, `profile`, and `https://www.googleapis.com/auth/youtube.force-ssl`.
   - Add every teammate and demo account as a **test user**.

   Testing mode allows up to 100 test users, and the YouTube grant expires after 7 days. That's fine for the course and avoids Google's verification review for a sensitive scope.
2. **Credentials → Create OAuth client ID → Web application**:
   - Authorized JavaScript origins: the `frontend_url` output from step 6 (the Cloud Run URL, `https://li-frontend-….run.app`), plus `http://localhost:5173`.
   - The client ID becomes `GOOGLE_CLIENT_ID` for the services and frontend. It isn't a secret.

## 6. Apply `envs/prod`

```sh
cd infra/terraform/envs/prod
cp terraform.tfvars.example terraform.tfvars   # ci_deploy_service_account = bootstrap output
terraform init -backend-config="bucket=$PROJECT-tfstate"
terraform apply                                 # ~15–20 min, mostly GKE and Cloud SQL
terraform output
```

What it creates:

| Resource | Notes |
|---|---|
| VPC `li` | Subnet with pod/service ranges, Private Google Access, Cloud NAT, private services access for Cloud SQL |
| GKE Autopilot cluster `li` | Private nodes on a least-privilege node service account; Secret Manager add-on enabled |
| Artifact Registry `li` | Docker images; keeps the last 10 versions; nodes pull, `github-deploy` pushes |
| Cloud SQL `li-pg` | Postgres 16, `db-f1-micro`, private IP only, IAM authentication; database `li` |
| Database users | `li_admin`, whose password is generated during the run and written to Cloud SQL and Secret Manager `db-admin-password` only (readable by the migrate workload); it is never stored in Terraform state. IAM users for `li-ingest` and `li-search` |
| Service accounts | `li-ingest`, `li-search`, `li-migrate`, each bound through Workload Identity to the Kubernetes service account of the same name in namespace `li` |
| Global IP `li-api` | The API is served at `<ip-with-dashes>.sslip.io` (output `api_hostname`), which is enough for a Google-managed certificate without buying a domain |
| Cloud Run `li-frontend` | The React app served by nginx (output `frontend_url`); public, scales 0–2 instances, runs as service account `li-frontend` with no roles. Starts with Google's placeholder image until the frontend deploy runs; `github-deploy` may deploy this service only |
| Azure `rg-li-prod` | In `northcentralus`; holds the backup storage from step 5 of the plan |

Check the configuration without credentials: `terraform -chdir=infra/terraform/envs/prod test` runs it against mocked providers.

To rotate the `li_admin` password, increment the default of `db_admin_password_version` in `variables.tf`, commit, and let the Terraform workflow apply it. Don't set it in `terraform.tfvars`: CI doesn't read that file, so its next apply would see a different version and rotate the password again. Cloud SQL and Secret Manager get the new value together; re-run the services deploy afterwards so the migrate Job runs.

**Terraform state holds no secrets.** The database password is write-only, and no deploy tokens exist: CI deploys with short-lived Workload Identity credentials.

## 7. Control cost

Rough monthly costs while everything runs. Check the [GCP pricing calculator](https://cloud.google.com/products/calculator) before relying on them.

| Item | Approx. / month |
|---|---|
| GKE Autopilot cluster fee | $0: the free-tier credit covers one cluster |
| Autopilot pods (ingest, search; Spot where possible) | $10–25 |
| Cloud SQL `db-f1-micro` + 10 GB SSD | ~$11 |
| HTTPS load balancer forwarding rule (created in step 4) | ~$18 |
| Cloud NAT, Artifact Registry, logging | a few dollars |
| Cloud Run `li-frontend` (scales to zero; free tier) | about $0 |

### Between test sessions: pause

Pausing keeps the cluster, the database, the images and the reserved IP, so the API hostname, `values.env`, the CSP and the OAuth origins all stay valid. It needs `gcloud`, `kubectl` and `gke-gcloud-auth-plugin` ([install](../local-development.md#install-cloud-tools-optional)), or Cloud Shell, which has all three.

```sh
make cloud-pause     # pods to 0, delete the Ingress (load balancer), stop Cloud SQL
make cloud-resume    # start Cloud SQL, pods back to 1, re-create the Ingress (~5–10 min)
make cloud-status    # what's running and billed right now
```

The script is `scripts/cloud-power.sh` (`DRY_RUN=1` prints the commands without running them). It uses the current `gcloud` project unless `GCP_PROJECT` is set.

| While paused | Approx. / month |
|---|---|
| Cloud SQL storage (10 GB SSD) | ~$2 |
| Reserved IP `li-api`, not attached to a load balancer | ~$7 |
| Autopilot (no pods), Cloud NAT, Artifact Registry | about $0 |

Things to know:

- **Terraform doesn't touch the Cloud SQL on/off state** (`ignore_changes` on `activation_policy`), so a `terraform apply`, including CI's, never restarts a paused database. Terraform still creates the instance running.
- **Deploys skip while paused** (step 8): they finish green with a warning and change nothing. After `make cloud-resume`, re-run the ones that skipped, e.g. `gh workflow run services-deploy.yml --ref main`.
- **The Deployments have no `replicas` field**, and an HPA leaves a Deployment at 0 replicas alone, so pods stay at 0 until `make cloud-resume` scales them back.
- **Resume re-applies only the Ingress** (label `app.kubernetes.io/component=ingress`). Re-applying the whole overlay would reset the image tags to the committed placeholders.
- The ManagedCertificate stays in the cluster while paused. If the API answers with a certificate error right after a resume, wait for the load balancer to finish provisioning (up to ~30 minutes).
- A paused Cloud SQL instance can't be backed up, so the nightly backup CronJob (step 5) fails while paused.

### When idle for longer: destroy

```sh
terraform -chdir=infra/terraform/envs/prod destroy   # bootstrap and its state stay
```

This brings the GCP cost to $0, but:

- **It deletes the database.** Make sure the nightly backup (step 5 of the plan) has run, or the data is disposable.
- **It releases the IP, which changes the API hostname.** After re-creating, update `values.env` and push to `main`; both deploys re-run because `values.env` changed, and the frontend build picks up the new API origin. The Cloud Run URL can change too when the service is re-created: update `CORS_ORIGINS` and the OAuth client's origins.

### Budget alert

In the GCP console, **Billing → Budgets & alerts**, create a budget for the project (for example $25) with email alerts at 50%, 90% and 100%. A budget only warns; it doesn't stop spending. It catches a forgotten `cloud-resume`.

## 8. Deploy from GitHub Actions

Three workflows deploy from `main`. Each runs in the `prod` environment, so each waits for an approval, and each first waits for CI to pass on the same commit (`wait-for-ci.yml`). They also run by hand: **Actions → Run workflow**, or `gh workflow run <file> --ref main`.

| Workflow | Runs on a push to `main` that touches | Does | While paused |
|---|---|---|---|
| `terraform.yml` | `infra/terraform/` | plan, then apply `envs/prod` as `github-terraform` / `id-li-github`. On PRs: a read-only plan as a PR comment | skips: refreshing the database users needs a running instance |
| `services-deploy.yml` | `services/`, `db/`, `deploy/k8s/` | build and push both images (tagged with the commit SHA), run the migrate Job, apply the app overlay, wait for the rollouts | skips: migrations need the database, and applying the overlay would re-create the load balancer |
| `frontend-deploy.yml` | `frontend/`, `values.env` | build the nginx image with `VITE_API_BASE` and `VITE_GOOGLE_CLIENT_ID` taken from `values.env` (the CSP's `connect-src` follows `VITE_API_BASE`), push it, `gcloud run deploy li-frontend` | runs: Cloud Run scales to zero anyway; the site shows API errors until resumed |

The pause check (`scripts/ci/check-paused.sh`) counts the environment as paused when Cloud SQL isn't `ALWAYS`/`RUNNABLE`, or (services only) when the namespace exists but the Ingress doesn't. A skipped run ends green with a warning and a summary saying what to re-run. Before the first apply and the first deploy, nothing counts as paused.

The approval comes before the plan is visible. Read the PR's plan comment, or what changed on `main`, before approving an apply.

### First deploy

1. Steps 1–6 done: bootstrap applied, GitHub variables and the `prod` environment set, `envs/prod` applied (by hand, or by running `terraform.yml`).
2. Fill `deploy/k8s/overlays/prod/values/values.env` from `terraform output` (each line names its output; `CORS_ORIGINS` is `frontend_url`), plus `GOOGLE_CLIENT_ID` and `PROFESSOR_EMAILS`. The services and frontend deploys refuse to run while it still has placeholders.
3. Push to `main` and approve the services and frontend deploys. The Google-managed certificate takes 15–60 minutes to become active after the first rollout. Until the frontend deploy runs, the Cloud Run URL shows Google's placeholder page.
4. Add the `frontend_url` output as an authorized JavaScript origin on the OAuth client (step 5), if it isn't there yet.

A push that touches both `infra/terraform/` and the services starts both workflows at once; nothing orders them. If the services deploy needs the infrastructure change, approve the Terraform run first and re-run the services deploy after it finishes.
