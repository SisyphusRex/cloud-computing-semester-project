# Bootstrap and provision the cloud infrastructure

One person does steps 1–5 once. After that, CI runs Terraform (step 4 of the [implementation plan](../implementation-plan.md)). Steps 6–7 apply to anyone who provisions or tears down the production environment.

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) 1.16.4. With [tfenv](https://github.com/tfutils/tfenv), `infra/terraform/.terraform-version` selects it automatically.
- [gcloud CLI](https://cloud.google.com/sdk/docs/install) and [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli).
- A GCP project with billing (GCP credits), and the Azure for Students subscription.
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
| in the `prod` GitHub environment | `github-deploy` | — | push images, deploy to GKE |
| on a pull request | `github-plan` (Viewer, read state) | `id-li-github-plan` (Reader) | `terraform plan -refresh=false -lock=false` |

Nothing else, including jobs on branch pushes outside the `prod` environment, can get credentials.

```sh
cd infra/terraform/bootstrap
cp terraform.tfvars.example terraform.tfvars   # fill in real IDs; git-ignored
terraform init -backend-config="bucket=$PROJECT-tfstate"
terraform apply
terraform output github_variables
```

If Azure reports an unregistered resource provider, register it and re-apply: `az provider register --namespace Microsoft.ManagedIdentity` (also `Microsoft.Web` for Static Web Apps).

## 4. Configure GitHub

In the repository settings:

1. **Variables** (Settings → Secrets and variables → Actions → Variables): add each entry from `github_variables`. None of them are secrets.
2. **Environment** (Settings → Environments): create `prod`. It's the only way into the powerful identities, so protect it:
   - **Required reviewers:** add the teammates, so every apply and deploy waits for an explicit approval. **Prevent self-review** stays off (team decision, 2026-10-15): whoever triggered a deploy may approve it.
   - Uncheck **Allow administrators to bypass configured protection rules**.
   - **Deployment branches and tags:** **Selected branches and tags** → `main` only.

   Without these, any workflow that names `environment: prod` gets admin-level credentials.

   **Pull requests into `main` are not enforced** (team decision, 2026-10-15). Collaborators can push straight to `main`, so the branch limit only keeps feature branches from deploying. Together with self-approval, one person can push to `main` and approve their own deploy; the approval is a deliberate confirmation step, not a second person's review. Before approving, look at what changed on `main` since the last deploy, especially `.github/workflows/` and `infra/`, because the workflow that runs is the one on `main` at that moment.

   To tighten this later, either check **Prevent self-review** (a second person approves every deploy) or add a branch ruleset on `main` requiring a pull request with one approval and an empty bypass list. Neither needs other changes.

## 5. Create the Google OAuth client (console only)

Terraform can't create OAuth clients for external users, so do this in the console under **APIs & Services**:

1. **OAuth consent screen**:
   - User type **External**, publishing status **Testing**.
   - Scopes: `openid`, `email`, `profile`, and `https://www.googleapis.com/auth/youtube.force-ssl`.
   - Add every teammate and demo account as a **test user**.

   Testing mode allows up to 100 test users, and the YouTube grant expires after 7 days. That's fine for the course and avoids Google's verification review for a sensitive scope.
2. **Credentials → Create OAuth client ID → Web application**:
   - Authorized JavaScript origins: the `frontend_url` output from step 6, plus `http://localhost:5173`.
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
| Azure `rg-li-prod` | Free-tier Static Web App `swa-li-prod` (output `frontend_url`) |

Check the configuration without credentials: `terraform -chdir=infra/terraform/envs/prod test` runs it against mocked providers.

To rotate the `li_admin` password, increment `db_admin_password_version` in `terraform.tfvars` and apply. Cloud SQL and Secret Manager get the new value together; re-run the migrate Job afterwards.

**What Terraform state still holds.** State never contains the database password, but it does contain the Static Web App deploy token (the azurerm provider stores it). Anyone who can read state, including the PR plan identity, could deploy the frontend. Reset the token in the Azure portal if that's ever a concern.

## 7. Control cost

Rough monthly costs while everything runs. Check the [GCP pricing calculator](https://cloud.google.com/products/calculator) before relying on them.

| Item | Approx. / month |
|---|---|
| GKE Autopilot cluster fee | $0: the free-tier credit covers one cluster |
| Autopilot pods (ingest, search; Spot where possible) | $10–25 |
| Cloud SQL `db-f1-micro` + 10 GB SSD | ~$11 |
| HTTPS load balancer forwarding rule (created in step 4) | ~$18 |
| Cloud NAT, Artifact Registry, logging | a few dollars |
| Static Web Apps (Free) | $0 |

Between work sessions:

```sh
# Stop Cloud SQL (storage is still billed), and start it again later
gcloud sql instances patch li-pg --activation-policy=NEVER
gcloud sql instances patch li-pg --activation-policy=ALWAYS

# Or remove the whole environment; bootstrap and its state stay
terraform -chdir=infra/terraform/envs/prod destroy
```

Destroying `envs/prod` deletes the database. Make sure the nightly backup (step 5 of the plan) has run, or the data is disposable.
