# Plan: Grafana Cloud monitoring

**Status:** proposed, for team review. Nothing here has been built yet.

This plan adds one Grafana Cloud dashboard showing our Google Cloud services and our Azure backup storage. It covers the monitoring deliverable for M3 and the dashboard part of step 5 in the [implementation plan](../implementation-plan.md).

## Why

The course requires at least one observability dashboard. Today our only monitoring is the "Database backup failed" alert, and we have no log-based metrics, so there's no single place to see the system's health.

## The approach

Grafana Cloud is a hosted service run by Grafana Labs. It would query Cloud Monitoring and Azure Monitor directly, so metrics aren't copied into it, no agents run in our cluster, and history stays in the two clouds.

- **Google access:** a new service account, `li-grafana`, with only `roles/monitoring.viewer`. It can't read raw logs, so charts use log-based metrics.
- **Azure access:** a new app registration, `li-grafana`, with `Monitoring Reader` on `rg-li-backup` only. Grafana's docs suggest Reader on the whole subscription, so step 2 tests whether the narrower role is enough.
- **Terraform owns the identities and roles, and a script owns the credentials.** This is the same split we use for the backup SAS in `scripts/cloud-backup-sas.sh`.
- **Dashboards are code, outside the release pipeline.** They go in a new Terraform root that's applied by hand. No Grafana token goes into GitHub, and a Grafana problem can't block a production release.
- **Alerts stay in Cloud Monitoring.** The remaining alerts from step 5 aren't part of this plan.

## What shaped the design

| Finding | Effect |
|---|---|
| Grafana Cloud can't use managed or workload identity for Azure | Azure needs an app registration with a client secret |
| Grafana Cloud's Google data source needs a service account key file | Google needs a long-lived key |
| Pull request plans can read Terraform state, and plan files can be downloaded on this public repository ([ADR 0004](../architecture_decision_records/0004-database-backups-to-azure.md)) | Neither credential may enter Terraform state or plans, including through `grafana_data_source` |
| CI's Azure identities can't create Entra apps, and `bootstrap` is applied by hand | The identities go in `bootstrap`, applied by the Azure subscription owner |
| The tenant allows app creation, and the GCP project has no organization above it | Nothing blocks creating either identity |
| `backup_succeeded` logs a numeric `bytes` field | A log-based metric can chart backup size |
| Azure's `BlobCount` and `BlobCapacity` report hourly | Azure charts can lag a backup by about an hour |

**This changes our security position.** CI and the app's access to Google stay keyless. We already have two long-lived secrets, `backup-sas` and `db-admin-password`, but both stay in Secret Manager. These two would be our first long-lived credentials held outside our own clouds, by a third party. They're read-only, limited to monitoring data, and can be rotated, but the security review needs to cover them.

## Before we start

The team needs to agree on three things:

1. **Grafana Cloud as a third party,** given the credentials above.
2. **The account owner.** Use a shared team email rather than a personal account, so access doesn't depend on one person.
3. **The free tier's user limit.** Sources disagreed on it, and it could be as low as 3 users. Sign up and check this first, along with whether the Google Cloud Monitoring and Azure Monitor data sources are available. If the limit is too low, this plan needs to change before anything is built.

## Steps

### 1. Log-based metrics

Released the normal way. In `infra/terraform/modules/monitoring/main.tf`, add a `google_logging_metric` for each of these:

| Metric | Filter |
|---|---|
| `backup_succeeded` | `jsonPayload.event="backup_succeeded"` |
| `backup_failed` | `jsonPayload.event="backup_failed"` |
| `backup_bytes` (a distribution, from `jsonPayload.bytes`) | `jsonPayload.event="backup_succeeded"` |
| `ingest_succeeded`, `ingest_failed` | The matching `jsonPayload.event` |
| `app_errors` | `resource.type="k8s_container"`, namespace `li`, `severity>=ERROR` |

Update that file's header comment too. The metrics only count from when they're created, so charts start empty.

### 2. Identities

Applied by hand in `infra/terraform/bootstrap`:

- A new `grafana.tf` with `google_service_account`, `google_project_iam_member`, `azuread_application`, `azuread_service_principal` and `azurerm_role_assignment`.
- The `hashicorp/azuread` provider in `versions.tf`, with the lock file updated.
- Outputs in `outputs.tf` for the Google email and Azure client ID. Neither is a secret.

The plan must say `5 to add, 0 to change, 0 to destroy`, with no secret or password attributes.

### 3. Grafana Cloud stack

By hand: create the free stack on grafana.com in a US region. Then create a Grafana service account token, keep it in a password manager, and export it locally as `GRAFANA_AUTH`, along with `GRAFANA_URL`.

### 4. Credentials script

Add a `cloud-grafana-credentials.sh` script to `scripts/`, with a `make cloud-grafana-credentials` target, modelled on `scripts/cloud-backup-sas.sh`. Each run:

1. Creates a new Google key, and resets the Azure client secret with `az ad app credential reset --years 1`.
2. Creates or updates the Grafana data sources through its API, with the fixed UIDs `li-gcp` and `li-azure`.
3. Sends credentials on stdin rather than as arguments, so they can't show up in a process list. Any temporary key file goes in `mktemp`, and an `EXIT` trap removes it with `shred`.
4. Deletes older Google keys, then prints the expiry date.

Running it again rotates both credentials. Add the rotation date to [todo.md](../todo.md), and delete both credentials when the project ends.

### 5. Dashboard as code

Add a new Terraform root, `grafana`, under `infra/terraform/`, with `versions.tf`, `main.tf` and the dashboard JSON. Its state uses the existing bucket under the prefix `grafana`. It holds a `grafana_folder` and a `grafana_dashboard`, but no data sources. Add the root to the validation loop in `.github/workflows/ci.yml`.

Build the dashboard in Grafana's editor, export the JSON and commit it. Refresh every 5 minutes.

| Row | Panels | Source |
|---|---|---|
| Health | Cloud SQL state, `app_errors`, API 5xx rate | Google Cloud |
| Frontend | Cloud Run requests, 5xx errors, response time | `run.googleapis.com` |
| API | Load balancer requests by status, latency | `loadbalancing.googleapis.com` |
| GKE | CPU and memory for `ingest` and `search`, restarts | `kubernetes.io` |
| Cloud SQL | CPU, memory, disk, connections | `cloudsql.googleapis.com` |
| Ingestion | `ingest_succeeded`, `ingest_failed` | Log-based metrics |
| Backups | `backup_succeeded`, `backup_failed`, `backup_bytes` | Log-based metrics |
| Azure | `BlobCount`, `BlobCapacity`, Transactions by response type, Availability | Azure Monitor |

Add a text panel explaining that flat charts are expected while the environment is paused.

### 6. Documentation

New files, which don't exist yet:

```
docs/architecture_decision_records/0005-monitoring-on-grafana-cloud.md
docs/runbooks/monitoring.md
```

- **ADR 0005** covers the third-party vendor, the two credentials held outside our clouds, and why they stay out of Terraform state.
- **The monitoring runbook** covers setup, rotating credentials, revoking a leak and teardown.
- **Claims this change makes untrue** need correcting in `infra/terraform/envs/prod/identities.tf`, [architecture.md](../architecture.md), the [bootstrap runbook](../runbooks/bootstrap.md) and the [root README](../../README.md). CI stays keyless, so most need narrowing rather than removing.
- **[Dashboard links](dashboard-links.md) and the [implementation plan](../implementation-plan.md)** need the dashboard and new identities added.
- **The [security review notes](../security/review-notes.md)** should list both credentials and their scopes.

## How we'll know it works

1. **Repository checks:** `terraform fmt -check -recursive`, `validate` in all three roots, the mocked-provider tests, and `make docs-check`.
2. **Least privilege:** IAM shows only `roles/monitoring.viewer` for `li-grafana`, and `az role assignment list` shows only `Monitoring Reader` on `rg-li-backup`.
3. **No leaks:** `terraform state pull | grep -ciE 'private_key|client_secret|password'` prints 0 in `bootstrap` and `grafana`, and `git status --short` shows no key files.
4. **Connections:** both data sources pass Grafana's health check.
5. **End to end:** after `make cloud-backup`, `backup_succeeded` and `backup_bytes` rise within minutes, and `BlobCount` goes up by one within about an hour.
6. **Failure path:** the forced failure in the [backup runbook](../runbooks/backup-and-restore.md#check-the-protections) shows up in `backup_failed`. Put the CronJob back afterwards.
7. **Pausing:** after `make cloud-pause` and `make cloud-resume`, charts resume with no change in Grafana.
8. **Rotation:** after running the script again, the old credentials stop working and the health checks still pass.

## Risks

- **University tenant:** the Azure app lives in WMU's tenant, so its policies or the owner's account status could change. Azure charts would stop, but nothing else would.
- **Third party:** Grafana Labs holds two credentials and can see our metrics.
- **Azure charts show storage, not recoverability:** they show that storage changed, not that a backup can be restored. The [restore test](../runbooks/backup-and-restore.md#test-a-restore) still does that.
- **Pauses:** charts go flat while the environment is paused, which needs explaining in a demo.
