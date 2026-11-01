# Environment and dashboard links

The values of our deployed environment, and where to look at the running system in the web consoles. None of these values are secrets. Google Cloud links open the project `lecture-indexer-511419` directly; sign in with an account that has access to it. The remaining alerts from step 5 of the [implementation plan](../implementation-plan.md) don't exist yet; they'll be added here.

## The app

| What | Link |
|---|---|
| Frontend (Cloud Run) | https://li-frontend-byshtpdfha-uc.a.run.app |
| API (load balancer) | https://34-128-137-19.sslip.io (`/search/courses` answers `401` without a sign-in) |

## Our environment

| What | Value |
|---|---|
| GCP project | `lecture-indexer-511419` (number `294292796743`), region `us-central1` |
| Terraform state | `gs://lecture-indexer-511419-tfstate` (versioned, public access blocked) |
| OAuth client ID | `294292796743-npo1ene9euu5v10tundn5inb1sval8n4.apps.googleusercontent.com` |
| Azure subscription | Azure for Students, `898a010f-f766-4657-b683-6fb3c7399a77`; resources in `northcentralus` |
| CI identities | GCP: `github-terraform`, `github-deploy`, `github-plan`. Azure: `id-li-github`, `id-li-github-plan` (resource group `rg-li-ci`) |
| GitHub `prod` environment | Deploys only from `main`; reviewers awojo, joshuajubenville, SisyphusRex; self-approval allowed; admin bypass on (team decision) |
| Backup storage | Account `libackupecd087147d`, container `https://libackupecd087147d.blob.core.windows.net/backups`, in `rg-li-backup` |
| Backup retention | Immutable for 30 days (unlocked policy), deleted at 35 days |
| Backup service account | `li-backup@lecture-indexer-511419.iam.gserviceaccount.com` |
| Backup upload credential | Secret Manager `backup-sas`; expires 2027-10-31 |
| Backup encryption public key | `age1zuvsq4vtwc49dwkdt8uknl3kh2z2rt52p8r3kmfag4n9a0kwz4sqes3nz2` |
| Backup alert | Cloud Monitoring policy "Database backup failed", by email |
| Grafana identities | Google: `li-grafana@lecture-indexer-511419.iam.gserviceaccount.com`. Azure: app `li-grafana`, client ID `4c811b16-fcda-46f0-89e9-0b99f08e6beb` |
| Grafana credential expiry | Azure secret: 2027-11-01. The Google key never expires |

## Grafana Cloud

| What | Link | Look for |
|---|---|---|
| Dashboard | https://silverlinden1722.grafana.net/d/lecture-indexer | Google Cloud services and Azure backup storage, on one page |
| Data sources | https://silverlinden1722.grafana.net/connections/datasources | `Google Cloud Monitoring` (`li-gcp`) and `Azure Monitor` (`li-azure`). The `grafanacloud-*` ones come with every stack, and we don't use them |

How to set it up and look after it: the [monitoring runbook](../runbooks/monitoring.md).

## Google Cloud

For a project-wide overview, use **Cloud Hub**: follow the link in the console's banner, or search the top bar for "Cloud Hub". It replaces the old project dashboard, which Google is deprecating.

| What | Link | Look for |
|---|---|---|
| GKE cluster | [Kubernetes clusters](https://console.cloud.google.com/kubernetes/list/overview?project=lecture-indexer-511419) | Cluster `li` |
| API pods | [Workloads](https://console.cloud.google.com/kubernetes/workload/overview?project=lecture-indexer-511419) | `ingest`, `search`, the `backup` CronJob, the `migrate` Job (filter by namespace `li`) |
| Load balancer and certificate | [Gateways, Services & Ingress](https://console.cloud.google.com/kubernetes/ingresses?project=lecture-indexer-511419) | Ingress `li-api` and its certificate status |
| Database | [Cloud SQL](https://console.cloud.google.com/sql/instances?project=lecture-indexer-511419) | `li-pg`; **Backups** lists the backups taken before releases with migrations |
| Frontend service | [Cloud Run](https://console.cloud.google.com/run?project=lecture-indexer-511419) | `li-frontend`; **Revisions** shows the traffic split and which revision is live |
| Container images | [Artifact Registry](https://console.cloud.google.com/artifacts?project=lecture-indexer-511419) | Repository `li`: `ingest`, `search`, `backup`, `frontend`, tagged by commit SHA |
| Secrets | [Secret Manager](https://console.cloud.google.com/security/secret-manager?project=lecture-indexer-511419) | `db-admin-password`, `backup-sas` |
| Logs | [Logs Explorer](https://console.cloud.google.com/logs/query?project=lecture-indexer-511419) | API requests: `jsonPayload.event="http_request"`; ingestion: `jsonPayload.event="ingest_failed"`; backups: `jsonPayload.event="backup_failed"` |
| Alerts | [Alerting](https://console.cloud.google.com/monitoring/alerting?project=lecture-indexer-511419) | Policy "Database backup failed" |
| Network | [VPC networks](https://console.cloud.google.com/networking/networks/list?project=lecture-indexer-511419) | VPC `li`, Cloud NAT, reserved IP `li-api` (34.128.137.19) |
| Access | [IAM](https://console.cloud.google.com/iam-admin/iam?project=lecture-indexer-511419) | The `github-*` (CI) and `li-*` (workload) service accounts and their roles |
| Cost | [Billing reports](https://console.cloud.google.com/billing/linkedaccount?project=lecture-indexer-511419) | Spend by service; budget alerts (runbook §7) |
| YouTube API quota | [YouTube Data API v3 quotas](https://console.cloud.google.com/apis/api/youtube.googleapis.com/quotas?project=lecture-indexer-511419) | Daily units used (10,000 a day; one registration costs 252) |

## Azure

| What | Link |
|---|---|
| Resource groups (`rg-li-ci`: CI identities; `rg-li-backup`: backups; `rg-li-prod`: empty) | https://portal.azure.com/#browse/resourcegroups |

## Labels and tags

Resources carry the same keys in both clouds: labels in Google Cloud, tags in Azure. Use them to filter a resource list, or to break down Billing reports. Some consoles hide the label column until you turn it on under the list's column settings.

| Key | Values |
|---|---|
| `app` | `lecture-indexer` |
| `environment` | `prod` for `envs/prod`; `shared` for what outlives it (`bootstrap`, the state bucket) |
| `managed-by` | `terraform`; `hand` for the state bucket |
| `component` | `api-cluster`, `api-load-balancer`, `container-images`, `database`, `frontend`, `monitoring`, `network`, `secrets`, `ci-identity`, `database-backups`, `terraform-state`, `unused` |

Azure tags also have `purpose`, a sentence saying what the resource is for. Google Cloud label values can't contain spaces, so there the Cloud Run service and Artifact Registry repository use their description field instead.

Some resources can't carry labels:

| Resource | What it is |
|---|---|
| VPC `li`, subnet `li-gke` | The private network for GKE and Cloud SQL |
| Router `li-router`, NAT `li-nat` | Outbound internet for the private nodes, e.g. to Azure Blob |
| Service accounts `li-ingest`, `li-search`, `li-migrate`, `li-backup` | One identity per workload |
| Service account and Azure app `li-grafana` | Read-only access for Grafana Cloud |
| Log-based metrics `app_errors`, `backup_*`, `ingest_*`, `searches`, `search_failed` | What the dashboard charts from the logs |
| Service accounts `li-nodes`, `li-frontend` | GKE nodes, and the Cloud Run frontend |
| Service accounts `github-terraform`, `github-deploy`, `github-plan` | GitHub Actions: apply, deploy, read-only plan |
| Workload Identity pool `github` | Lets GitHub Actions sign in to Google Cloud without keys |
| Load balancer resources named `k8s2-…` | Created by GKE for the Ingress `li-api`; they go away on `make cloud-pause` |

## GitHub

| What | Link |
|---|---|
| Workflow runs (CI, Release, Roll back) | https://github.com/SisyphusRex/cloud-computing-semester-project/actions |
| Releases (every `prod-*` tag) | https://github.com/SisyphusRex/cloud-computing-semester-project/releases |
| Deployments to `prod` (approvals and history) | https://github.com/SisyphusRex/cloud-computing-semester-project/deployments |
