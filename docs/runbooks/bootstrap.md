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
gcloud storage buckets update gs://$PROJECT-tfstate \
  --update-labels=app=lecture-indexer,environment=shared,managed-by=hand,component=terraform-state
```

## 3. Apply `bootstrap/`

This creates keyless GitHub Actions access to both clouds. A Workload Identity pool only accepts this repository's tokens, and which identity a job gets depends on how the job runs:

| Job runs… | GCP service account | Azure identity | Can |
|---|---|---|---|
| in the `prod` GitHub environment | `github-terraform` | `id-li-github` (Contributor) | apply Terraform |
| in the `prod` GitHub environment | `github-deploy` | — | push images, deploy to GKE, read Cloud SQL's state (the pause check) |
| on a pull request | `github-plan` (Viewer, read state) | `id-li-github-plan` (Reader) | `terraform plan -refresh=false -lock=false` |
| in the `prod-plan` GitHub environment | `github-plan` | `id-li-github-plan` | the read-only plan in `release.yml`, before the approval |

Nothing else, including jobs on branch pushes outside these environments, can get credentials.

```sh
cd infra/terraform/bootstrap
cp terraform.tfvars.example terraform.tfvars   # fill in real IDs; git-ignored
terraform init -backend-config="bucket=$PROJECT-tfstate"
terraform apply
terraform output github_variables
```

If Azure reports an unregistered resource provider, register it and re-apply: `az provider register --namespace Microsoft.ManagedIdentity`. A `RequestDisallowedByAzure` error means a resource is in a region the subscription doesn't allow (see Prerequisites).

**Token subjects.** The bindings match GitHub's OIDC token subject exactly. This repository uses GitHub's *immutable* subjects, which include the owner and repository IDs (`repo:SisyphusRex@84345902/cloud-computing-semester-project@1403489193:environment:prod`), so `github_subject_prefix` in `variables.tf` holds that prefix. For a fork or a renamed repository, set it from `gh api repos/OWNER/REPO/actions/oidc/customization/sub -q .sub_claim_prefix`. A wrong prefix shows up in CI as `Permission 'iam.serviceAccounts.getAccessToken' denied` right after a successful sign-in.

## 4. Configure GitHub

In the repository settings:

1. **Variables** (Settings → Secrets and variables → Actions → Variables): add each entry from `github_variables`. None of them are secrets.
2. **Environment `prod-plan`**: deployment branches `main` only, no reviewers. It only gives the read-only plan identities to `release.yml`'s plan job, so the plan can be read before anyone approves.
3. **Environment** (Settings → Environments): create `prod`. It's the only way into the powerful identities, so protect it:
   - **Required reviewers:** add the teammates, so every apply and deploy waits for an explicit approval. **Prevent self-review** stays off (team decision, 2026-10-15): whoever triggered a deploy may approve it.
   - **Allow administrators to bypass configured protection rules** stays on (team decision, 2026-10-18). A repository admin can then deploy without an approval, so the approval binds everyone else; turn it off to make it binding for admins too.
   - **Deployment branches and tags:** **Selected branches and tags** → `main` only.

   Without these, any workflow that names `environment: prod` gets admin-level credentials.

   **Pull requests into `main` are not enforced** (team decision, 2026-10-15). Collaborators can push straight to `main`, so the branch limit only keeps feature branches from deploying. Together with self-approval, one person can push to `main` and approve their own deploy; the approval is a deliberate confirmation step, not a second person's review. Before approving, look at what changed on `main` since the last deploy, especially `.github/workflows/` and `infra/`, because the workflow that runs is the one on `main` at that moment.

   To tighten this later, turn off the admin bypass, check **Prevent self-review** (a second person approves every deploy) or add a branch ruleset on `main` requiring a pull request with one approval and an empty bypass list. Neither needs other changes.

## 5. Create the Google OAuth client (console only)

Terraform can't create OAuth clients for external users, so do this in the console under [**Google Auth Platform**](https://console.cloud.google.com/auth/overview). On a new project, **Get started** asks for the app name, a support email and a contact email first.

1. **Audience**:
   - User type **External**, publishing status **Testing**.
   - Add every teammate and demo account as a **test user**.

   Testing mode allows up to 100 test users, and the YouTube grant expires after 7 days. That's fine for the course and avoids Google's verification review for a sensitive scope.
2. **Data Access → Add or remove scopes**, then **Update** and **Save**: `openid`, `.../auth/userinfo.email`, `.../auth/userinfo.profile`, and `https://www.googleapis.com/auth/youtube.force-ssl` (sensitive, which is expected).
3. **Clients → Create client → Web application**:
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
| Artifact Registry `li` | Docker images; keeps the newest 10 versions of each image, plus anything under 30 days old; nodes pull, `github-deploy` pushes |
| Cloud SQL `li-pg` | Postgres 16, `db-f1-micro`, private IP only, IAM authentication; database `li` |
| Database users | `li_admin`, whose password is generated during the run and written to Cloud SQL and Secret Manager `db-admin-password` only (readable by the migrate and backup workloads); it is never stored in Terraform state. IAM users for `li-ingest` and `li-search` |
| Service accounts | `li-ingest`, `li-search`, `li-migrate`, `li-backup`, each bound through Workload Identity to the Kubernetes service account of the same name in namespace `li` |
| Global IP `li-api` | The API is served at `<ip-with-dashes>.sslip.io` (output `api_hostname`), which is enough for a Google-managed certificate without buying a domain |
| Cloud Run `li-frontend` | The React app served by nginx (output `frontend_url`); public, scales 0–2 instances, runs as service account `li-frontend` with no roles. Starts with Google's placeholder image until the frontend deploy runs; `github-deploy` may deploy this service only |
| Azure `rg-li-prod` | In `northcentralus`; empty. Backups are in `rg-li-backup`, from `bootstrap/`, so destroying this environment leaves them ([backup runbook](backup-and-restore.md)) |
| Secret `backup-sas` | The upload credential for backups. Starts empty: `make cloud-backup-sas` adds the value, so it never reaches Terraform state |

Check the configuration without credentials: `terraform -chdir=infra/terraform/envs/prod test` runs it against mocked providers.

To rotate the `li_admin` password, increment the default of `db_admin_password_version` in `variables.tf`, commit, and release it. Don't set it in `terraform.tfvars`: CI doesn't read that file, so its next apply would see a different version and rotate the password again. Cloud SQL and Secret Manager get the new value together, and the migrate Job in the same release logs in with it.

To query the database by hand (it has only a private IP), see [Accessing the production database](../security/database-access.md).

**Terraform state holds no secrets.** The database password is write-only, and no deploy tokens exist: CI deploys with short-lived Workload Identity credentials. Grafana's credentials are made by a script to stay out of state ([monitoring runbook](monitoring.md)).

## 7. Control cost

Rough monthly costs while everything runs: about $40–60 in total, or about $9 while [paused](#between-test-sessions-pause). Check the [GCP pricing calculator](https://cloud.google.com/products/calculator) before relying on them.

| Item | Approx. / month |
|---|---|
| GKE Autopilot cluster fee | $0: the free-tier credit covers one cluster |
| Autopilot pods (ingest, search; Spot where possible) | $10–25 |
| Cloud SQL `db-f1-micro` + 10 GB SSD | ~$11 |
| HTTPS load balancer forwarding rule (created by the first release, step 8) | ~$18 |
| Cloud NAT, Artifact Registry, logging | a few dollars |
| Cloud Run `li-frontend` (scales to zero; free tier) | about $0 |
| Azure Blob backups in `rg-li-backup` (Cool tier, LRS; billed even while paused) | not estimated; see the Azure cost view |

### Between test sessions: pause

Pausing keeps the cluster, the database, the images and the reserved IP, so the API hostname, `values.env`, the CSP and the OAuth origins all stay valid. It needs `gcloud`, `kubectl` and `gke-gcloud-auth-plugin` ([install](../local-development.md#install-cloud-tools-optional)), or Cloud Shell, which has all three.

```sh
make cloud-pause     # pods to 0, delete the Ingress (load balancer), stop Cloud SQL
make cloud-resume    # start Cloud SQL, pods back to 1, re-create the Ingress (~15–20 min, then 5–10 for the load balancer)
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
- **Releases skip while paused** (step 8): they finish green with a warning and change nothing. A rollback **fails** instead, because nothing was rolled back. After `make cloud-resume`, re-run the release: **Actions → Release → Run workflow** on `main`, or `gh workflow run release.yml --ref main`.
- **The Deployments have no `replicas` field**, and an HPA leaves a Deployment at 0 replicas alone, so pods stay at 0 until `make cloud-resume` scales them back.
- **Resume re-applies only the Ingress** (label `app.kubernetes.io/component=ingress`). Re-applying the whole overlay would reset the image tags to the committed placeholders.
- The ManagedCertificate stays in the cluster while paused. If the API answers with a certificate error right after a resume, wait for the load balancer to finish provisioning (up to ~30 minutes).
- **`make cloud-pause` backs up the database first,** and stops with nothing changed if that fails. A paused Cloud SQL instance can't be backed up, so the nightly CronJob is suspended until `make cloud-resume`. `make cloud-pause SKIP_BACKUP=1` skips the backup, for example when pausing because backups are broken.

### When idle for longer: destroy

```sh
terraform -chdir=infra/terraform/envs/prod destroy   # bootstrap and its state stay
```

This brings the GCP cost to $0, but:

- **It deletes the database.** Run `make cloud-backup` first, or make sure the data is disposable. The backups stay in Azure, in `rg-li-backup` ([backup runbook](backup-and-restore.md)).
- **`backup-sas` comes back empty** after a re-create. Run `make cloud-backup-sas` before the next release.
- **It releases the IP, which changes the API hostname.** After re-creating, update `values.env` and release it; the frontend build picks up the new API origin. The Cloud Run URL can change too when the service is re-created: update `CORS_ORIGINS` and the OAuth client's origins.

### Budget alert

In the GCP console, **Billing → Budgets & alerts**, create a budget for the project (for example $25) with email alerts at 50%, 90% and 100%. A budget only warns; it doesn't stop spending. It catches a forgotten `cloud-resume`.

## 8. Deploy from GitHub Actions

Every push to `main` starts one **Release** run (`release.yml`): a review sheet and the real Terraform plan first, then **one** approval in `prod` runs the apply, a database backup (if there are new migrations), migrations, the services, and the frontend, in that order. Then it tags the commit `prod-YYYY-MM-DD.N`. `rollback.yml` returns to an earlier tag. What to check before approving, and how to roll back: [release process](../release-process.md).

| Job | Identity | While paused |
|---|---|---|
| `plan` (environment `prod-plan`, no reviewers) | `github-plan` / `id-li-github-plan` | stops the release here with a warning; nobody is asked to approve |
| `release` (environment `prod`, approval) | `github-terraform` / `id-li-github` for the apply and the backup, then `github-deploy` | — |

The pause check (`scripts/ci/check-paused.sh`) counts the environment as paused when Cloud SQL isn't `ALWAYS`/`RUNNABLE`, or when the `li` namespace carries the `lecture-indexer/paused=true` annotation that `make cloud-pause` sets (and `make cloud-resume` removes last). Before the first deploy, nothing counts as paused. (It used to infer a pause from a missing Ingress, which a failed first release also leaves behind.) Pull requests that touch `infra/terraform/` also get a read-only plan comment from `terraform.yml`.

### First deploy

1. Steps 1–6 done: bootstrap applied, GitHub variables and the `prod` and `prod-plan` environments set, `envs/prod` applied by hand.
2. Fill `deploy/k8s/overlays/prod/values/values.env` from `terraform -chdir=infra/terraform/envs/prod output` (each line names its output), plus `GOOGLE_CLIENT_ID`. The release refuses to run while it still contains `REPLACE_ME`, `PROJECT_ID` or `0-0-0-0`. Check the result with `make k8s-check`, or let CI do it.

   | Line | Value |
   |---|---|
   | `GOOGLE_CLIENT_ID` | The OAuth client ID from step 5 |
   | `CORS_ORIGINS` | `frontend_url` |
   | `CLOUDSQL_CONNECTION_NAME` | `cloudsql.connection_name` |
   | `INGEST_DB_USER`, `SEARCH_DB_USER` | The service account emails without `.gserviceaccount.com` |
   | `MIGRATE_GRANTS` | `migrate_grants` |
   | `INGEST_GSA`, `SEARCH_GSA`, `MIGRATE_GSA` | `workload_service_accounts` |
   | `API_HOSTNAME` | `api_hostname` |
   | `DB_ADMIN_SECRET_VERSION` | `cloudsql.admin_password_secret` + `/versions/latest` |
   | `BACKUP_*` | See the [backup runbook](backup-and-restore.md#first-time-setup) |
3. Add the `frontend_url` output (`https://li-frontend-….run.app`) as an authorized JavaScript origin on the OAuth client (step 5), exactly, including `https://` and no trailing slash. Keep `http://localhost:5173`. Changes can take a few minutes to apply.
4. Merge into `main`, read the review sheet and the plan (it should show no changes), and approve. The Google-managed certificate takes 15–60 minutes after the first rollout, so on the first release the API check only warns. To watch it:

   ```sh
   gcloud container clusters get-credentials li --region us-central1
   kubectl -n li describe managedcertificate li-api   # wait for Status: Active
   ```

   Optionally, test the rollback once: **Actions → Roll back → Run workflow** with the new tag. It redeploys the same release and should change nothing.
5. **Create the first admin.** Sign-in is invite-only ([ADR 0002](../architecture_decision_records/0002-invite-only-users-and-admin-roles.md)), so nobody can sign in yet:

   ```sh
   make cloud-create-admin EMAIL=you@gmail.com   # the Google account you'll sign in with
   ```

   It runs `li-admin` as a one-off Job with the database-admin credentials (`scripts/cloud-admin.sh`), in the deployed ingest image; the environment must be running. Then sign in, open **Admin**, and invite the rest of the team (tick *Admin* for anyone who should invite others). `make cloud-admin ARGS=list` shows every account.
6. **Verify end to end.** Once the certificate is active, `curl -i https://<api_hostname>/search/courses` returns `401` (the request reached the Search API, which needs a sign-in), and `curl <frontend_url>/health` returns `ok` (not `/healthz`: Cloud Run reserves paths ending in `z`). On the Cloud Run URL, sign in with Google, open **Manage** as a professor, register a video with auto-generated captions, search a spoken word as a student, and check that the link opens YouTube at the right moment.
7. **Pause when done:** `make cloud-pause`, and `make cloud-resume` next time.
