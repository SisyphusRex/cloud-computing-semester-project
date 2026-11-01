# ADR 0005: Monitoring dashboard on Grafana Cloud

- **Status:** Accepted
- **Date:** 2026-11-01
- **Changes:** where the dashboard lives in the [implementation plan](../implementation-plan.md), step 5 (Grafana Cloud, not `modules/monitoring`)

## Context

The course requires at least one observability dashboard, and it's part of the M3 deliverable. Until now, our only monitoring was the backup failure alert. We wanted one page covering both clouds, without running anything new.

Three things shaped the design:

- **Grafana Cloud runs outside our clouds,** so it can't use the keyless sign-in that CI and our pods use. Azure needs an app registration with a client secret, and Google needs a service account key file.
- **The repository is public, and read-only pull request plans can read Terraform state** ([ADR 0004](0004-database-backups-to-azure.md)). So those credentials can't be in state, which rules out `grafana_data_source`.
- **Azure holds only backups,** and our backup job already logs its result to Google Cloud.

## Decision

| Choice | What | Why |
|---|---|---|
| Hosting | Grafana Cloud's free tier, run by Grafana Labs | Nothing for us to host, patch or secure |
| Data flow | Grafana queries Cloud Monitoring and Azure Monitor directly | No agents, and nothing copied out: history stays in the two clouds |
| Google access | `li-grafana` service account with only `roles/monitoring.viewer` | Can't change anything, or read raw logs, the database or secrets |
| Azure access | `li-grafana` app registration with only `Monitoring Reader` on `rg-li-backup` | Narrower than the subscription-wide Reader Grafana's docs suggest, and tested to be enough. It can't read blobs |
| Log data | Log-based metrics in `modules/monitoring` | Charts backups and ingestion without giving Grafana access to raw logs |
| Identities | `infra/terraform/bootstrap`, applied by hand | They outlive `envs/prod`, and CI's identities can't create Entra apps |
| Credentials | `scripts/cloud-grafana-credentials.sh`, not Terraform | Keeps them out of state, the same split as the backup SAS |
| Dashboard | `infra/terraform/grafana`, applied by hand | No Grafana token in GitHub, and a Grafana problem can't block a release |
| Alerts | Stay in Cloud Monitoring | Grafana only displays; a Grafana outage can't silence an alert |

## Alternatives considered

| Alternative | Why not |
|---|---|
| Cloud Monitoring dashboard only | Simpler, keyless and free, and the safer choice. It can't show Azure metrics directly, and the team wanted both clouds on one page |
| Azure Managed Grafana | Hourly and per-user charges against limited student credit. Its built-in identity covers Azure only, so it would still need a Google key |
| Self-hosted Grafana on Container Apps | We'd have to run, patch and secure a public login page, and persist its state |
| Credentials in `grafana_data_source` | Puts both credentials in Terraform state |
| Applying dashboards in the release pipeline | Puts a Grafana admin token in GitHub, and ties releases to a third party |

## Consequences

- **Two long-lived credentials now sit outside our clouds.** `backup-sas` and `db-admin-password` are also long-lived, but they stay in Secret Manager. These are held by a third party. They're read-only and limited to monitoring data, but a leak would expose that data until they're revoked: see the [monitoring runbook](../runbooks/monitoring.md#revoke-a-leaked-credential).
- **Someone has to rotate them.** The Azure secret lasts a year. The Google key never expires, so nothing forces its rotation.
- **Only the app's owner can rotate the Azure secret.** The script finds the app through `az ad app list --show-mine`.
- **The Azure app lives in WMU's tenant,** so its policies or the owner's account status could change. Azure charts would stop, but nothing else would.
- **Azure's charts show storage, not recoverability.** The [restore test](../runbooks/backup-and-restore.md#test-a-restore) still proves a backup works.
- **An app without an owner can't be fixed by a non-admin user.** Our first app was created with no owner, because `azuread_application` doesn't add one, and it couldn't be changed or given a service principal. `grafana.tf` now sets `owners`, and the old app needs removing by WMU IT ([to-do list](../todo.md#finish-the-grafana-setup)).
