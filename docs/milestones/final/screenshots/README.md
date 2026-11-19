# Screenshots of the running system

Captured on 2026-11-19 with Claude in Chrome, from production and the cloud consoles. This is a dated record, so don't update these images when the system changes.

**Redacted before each capture:** email addresses, people's names, Google and Azure account avatars, the GCP project ID and number, the Azure tenant name, and the Grafana stack name. The redaction only changed what the page displayed. The console header on the Google Cloud pages is blurred.

All 24 are also collected, one per page with these captions, in [LectureIndexer_Screenshots.pdf](LectureIndexer_Screenshots.pdf).

| File | What it shows |
|---|---|
| [01-app-signin.png](01-app-signin.png) | The sign-in page |
| [02-app-courses.png](02-app-courses.png) | The course list, as a student |
| [03-app-course.png](03-app-course.png) | A course page, with its lectures listed under the search bar |
| [04-app-search-results.png](04-app-search-results.png) | Search results for "Michigan", with highlighted excerpts and timestamps |
| [05-app-search-player.png](05-app-search-player.png) | The embedded player opened at a result's timestamp (3:25). The video frame and channel name are YouTube's and weren't redacted |
| [06-app-manage.png](06-app-manage.png) | The Manage page in the professor role. This account owns no courses, so only the create-course form shows |
| [07-app-admin.png](07-app-admin.png) | The Admin page: invitations, roles, and admin flags |
| [08-grafana-health.png](08-grafana-health.png) | Grafana dashboard health row. Backups shows Down: no backup had run since about 2026-11-18 |
| [09-grafana-api-gke.png](09-grafana-api-gke.png) | Load balancer requests and latency; Ingest and Search pod counts |
| [10-grafana-cloudsql-ingestion.png](10-grafana-cloudsql-ingestion.png) | Cloud SQL CPU, memory, disk, and connections; ingestion counts |
| [11-grafana-search-backups.png](11-grafana-search-backups.png) | Searches and search failures; backup counts |
| [12-grafana-azure-storage.png](12-grafana-azure-storage.png) | Backup results over 7 days, and Azure backup storage |
| [13-github-ci-run.png](13-github-ci-run.png) | A passing CI run with all 8 jobs |
| [14-github-release-run.png](14-github-release-run.png) | A release run: CI check, review sheet, read-only plan, release, tag |
| [15-github-release-steps.png](15-github-release-steps.png) | The release job's 7 numbered steps. Steps 1 and 2 were skipped because the release had no Terraform changes or migrations |
| [16-github-releases.png](16-github-releases.png) | The Releases page with `prod-*` tags |
| [17-gcp-gke-workloads.png](17-gcp-gke-workloads.png) | GKE workloads: the `ingest` and `search` Deployments and the `backup` CronJob |
| [18-gcp-cloudrun-revisions.png](18-gcp-cloudrun-revisions.png) | Cloud Run `li-frontend` revisions, traffic, and autoscaling (max 2 instances) |
| [19-gcp-cloudsql.png](19-gcp-cloudsql.png) | Cloud SQL `li-pg`: PostgreSQL 16, 1 vCPU, single zone |
| [20-gcp-ingress.png](20-gcp-ingress.png) | The `li-api` Ingress (external HTTPS load balancer) |
| [21-gcp-secret-manager.png](21-gcp-secret-manager.png) | Secret Manager: `backup-sas` and `db-admin-password` (names only) |
| [22-gcp-alert-policy.png](22-gcp-alert-policy.png) | The "Database backup failed" alert policy |
| [23-azure-backup-blobs.png](23-azure-backup-blobs.png) | Encrypted `.dump.age` backups in the Azure `backups` container, Cool tier |
| [24-azure-immutability-policy.png](24-azure-immutability-policy.png) | The container's 30-day time-based retention policy (unlocked) |
