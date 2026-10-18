# Dashboard links

Where to look at the running system in the web consoles. Google Cloud links open the project `lecture-indexer-511419` directly; sign in with an account that has access to it. The monitoring dashboard and alerts from step 5 of the [implementation plan](../milestones/m2_prototype_review/implementation-plan.md) will be added here once they exist.

## The app

| What | Link |
|---|---|
| Frontend (Cloud Run) | https://li-frontend-byshtpdfha-uc.a.run.app |
| API (load balancer) | https://34-128-137-19.sslip.io (`/search/courses` answers `401` without a sign-in) |

## Google Cloud

For a project-wide overview, use **Cloud Hub**: follow the link in the console's banner, or search the top bar for "Cloud Hub". It replaces the old project dashboard, which Google is deprecating.

| What | Link | Look for |
|---|---|---|
| GKE cluster | [Kubernetes clusters](https://console.cloud.google.com/kubernetes/list/overview?project=lecture-indexer-511419) | Cluster `li` |
| API pods | [Workloads](https://console.cloud.google.com/kubernetes/workload/overview?project=lecture-indexer-511419) | `ingest`, `search`, the `migrate` Job (filter by namespace `li`) |
| Load balancer and certificate | [Gateways, Services & Ingress](https://console.cloud.google.com/kubernetes/ingresses?project=lecture-indexer-511419) | Ingress `li-api` and its certificate status |
| Database | [Cloud SQL](https://console.cloud.google.com/sql/instances?project=lecture-indexer-511419) | `li-pg`; **Backups** lists the backups taken before releases with migrations |
| Frontend service | [Cloud Run](https://console.cloud.google.com/run?project=lecture-indexer-511419) | `li-frontend`; **Revisions** shows the traffic split and which revision is live |
| Container images | [Artifact Registry](https://console.cloud.google.com/artifacts?project=lecture-indexer-511419) | Repository `li`: `ingest`, `search`, `frontend`, tagged by commit SHA |
| Secrets | [Secret Manager](https://console.cloud.google.com/security/secret-manager?project=lecture-indexer-511419) | `db-admin-password` |
| Logs | [Logs Explorer](https://console.cloud.google.com/logs/query?project=lecture-indexer-511419) | API requests: `jsonPayload.event="http_request"`; ingestion: `jsonPayload.event="ingest_failed"` |
| Network | [VPC networks](https://console.cloud.google.com/networking/networks/list?project=lecture-indexer-511419) | VPC `li`, Cloud NAT, reserved IP `li-api` (34.128.137.19) |
| Access | [IAM](https://console.cloud.google.com/iam-admin/iam?project=lecture-indexer-511419) | The `github-*` (CI) and `li-*` (workload) service accounts and their roles |
| Cost | [Billing reports](https://console.cloud.google.com/billing/linkedaccount?project=lecture-indexer-511419) | Spend by service; budget alerts (runbook §7) |
| YouTube API quota | [YouTube Data API v3 quotas](https://console.cloud.google.com/apis/api/youtube.googleapis.com/quotas?project=lecture-indexer-511419) | Daily units used (10,000 a day; one registration costs 252) |

## Azure

| What | Link |
|---|---|
| Resource groups (`rg-li-ci`: CI identities; `rg-li-prod`: backups) | https://portal.azure.com/#browse/resourcegroups |

## GitHub

| What | Link |
|---|---|
| Workflow runs (CI, Release, Roll back) | https://github.com/SisyphusRex/cloud-computing-semester-project/actions |
| Releases (every `prod-*` tag) | https://github.com/SisyphusRex/cloud-computing-semester-project/releases |
| Deployments to `prod` (approvals and history) | https://github.com/SisyphusRex/cloud-computing-semester-project/deployments |
