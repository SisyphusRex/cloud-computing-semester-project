# Monitoring

How the Grafana Cloud dashboard is set up, and how to look after it. The design and its limits are in [ADR 0005](../architecture_decision_records/0005-monitoring-on-grafana-cloud.md). The dashboard's address is in [Environment and dashboard links](../monitoring/dashboard-links.md#grafana-cloud).

| Command | What it does |
|---|---|
| `make cloud-grafana-credentials` | Creates or rotates both credentials, and stores them in Grafana |
| `terraform apply` in `infra/terraform/grafana` | Publishes the dashboard |

## What's where

| Part | Where | Applied by |
|---|---|---|
| Log-based metrics | `infra/terraform/modules/monitoring` | A normal release |
| Identities and roles | `infra/terraform/bootstrap/grafana.tf` | Hand, by the Azure app's owner |
| Credentials and data sources | `scripts/cloud-grafana-credentials.sh` | Hand |
| Dashboard | `infra/terraform/grafana` | Hand |

## Sign in to Grafana from a terminal

The script and Terraform both need these. The token is a Grafana service account token, with the Admin role:

```sh
export GRAFANA_URL=https://silverlinden1722.grafana.net
GRAFANA_AUTH=$(age -d ~/li-grafana-token.age) && export GRAFANA_AUTH
```

To replace a lost or expired token, go to **Administration → Users and access → Service accounts** in Grafana, and add a new token to `li-automation`. It's only shown once. Save it encrypted, outside this repository:

```sh
read -rs GRAFANA_AUTH && export GRAFANA_AUTH     # paste the token, then press Enter
printf '%s' "$GRAFANA_AUTH" | age -p -o ~/li-grafana-token.age
```

## Set it up from scratch

Do these in order, from the repository root. Each step needs the one before it.

1. **Release** the log-based metrics, if they aren't live already.
2. **Apply the identities.** The person who does this becomes the Azure app's owner, and is the only one who can rotate its secret:
   ```sh
   cd infra/terraform/bootstrap
   terraform init -backend-config="bucket=<project>-tfstate"
   terraform apply
   cd ../../..
   ```
3. **Create the Grafana stack** on grafana.com, in a US region, and a service account with the Admin role and a token.
4. **Store the credentials:** `make cloud-grafana-credentials`.
5. **Test the data sources.** In Grafana, go to **Connections → Data sources**, open each one, and click **Save & test**. A new Azure secret can take a minute to work.
   - **Google Cloud Monitoring** should say "Successfully queried the Google Cloud Monitoring API."
   - **Azure Monitor** reports "One or more health checks failed" because we have no Log Analytics workspace. That's expected: only the Azure Monitor check has to pass.
6. **Publish the dashboard:**
   ```sh
   cd infra/terraform/grafana
   terraform init -backend-config="bucket=<project>-tfstate"
   terraform apply
   ```

## Change the dashboard

The dashboard is `infra/terraform/grafana/dashboards/lecture-indexer.json`. **Changes made only in Grafana are overwritten by the next apply.** Edit the panel in Grafana if that's easier, then use **Share → Export** to copy the JSON into that file. Commit it, then run `terraform apply`.

Panels refer to the data sources by their fixed UIDs, `li-gcp` and `li-azure`. A new log-based metric is charted as `logging.googleapis.com/user/<name>`, and only counts from when it's created.

## Read the dashboard

- **Empty or flat charts** are expected while the environment is paused.
- **A "No data" panel with a warning icon** means the metric has never had a value, or doesn't exist. `ingest_failed`, `backup_failed` and `search_failed` look like this until the first failure.
- **Azure's storage charts report hourly,** so they can lag a backup by about an hour.
- **Backup size is approximate.** It's a distribution, so it shows about 24.6 kB for a 22.7 kB backup. The exact size is in the `backup_succeeded` log line.
- **Cloud SQL memory near 100%** has been normal on `db-f1-micro` so far. Look here first if queries slow down.

## Rotate the credentials

`make cloud-grafana-credentials` replaces both, deletes the old Google keys, and prints the Azure secret's expiry date. Put that date in a calendar. The Google key never expires, so rotate it at the same time.

You must be signed in to `az` as an owner of the `li-grafana` app, and to `gcloud` as someone who can create keys for the service account.

## Revoke a leaked credential

1. **Rotate both at once:** `make cloud-grafana-credentials`. The old Google key and Azure secret stop working when it finishes.
2. **If Grafana itself may be compromised,** or the script can't run, cut access directly:
   ```sh
   gcloud iam service-accounts keys list --iam-account=li-grafana@<project>.iam.gserviceaccount.com --managed-by=user
   gcloud iam service-accounts keys delete <key id> --iam-account=li-grafana@<project>.iam.gserviceaccount.com
   az ad app credential list --id <client id>
   az ad app credential delete --id <client id> --key-id <key id>
   ```
3. **If the Grafana token leaked,** delete it in Grafana under `li-automation`, and create a new one.

Neither identity can change anything or read the database, secrets or backups. The exposure is monitoring data.

## Tearing down

`terraform destroy` on `envs/prod` deletes the log-based metrics, but not the identities or the dashboard. Those panels stop working until the metrics are recreated, and their counts restart.

To remove everything at the end of the project:

1. Delete the Google key and Azure secret, as in [Revoke a leaked credential](#revoke-a-leaked-credential).
2. Run `terraform destroy` in `infra/terraform/grafana`.
3. Remove `bootstrap/grafana.tf` and its outputs, then apply `bootstrap`.
4. Delete the Grafana stack on grafana.com, and `~/li-grafana-token.age`.
