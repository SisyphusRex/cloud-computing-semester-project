# Azure backup setup

What we did on 2026-10-31 to start backing up the production database to Azure, in order, with the results and the problems we hit. This is the record of that setup. The design is in [ADR 0004](../../architecture_decision_records/0004-database-backups-to-azure.md), and day-to-day commands are in the [backup runbook](../../runbooks/backup-and-restore.md).

> **Record of 2026-10-31.** The states below are as they were that day. For how to do this now, use the [backup runbook](../../runbooks/backup-and-restore.md); for what's still open, the [to-do list](../../todo.md).

Times are UTC. None of the values here are secrets. The private key, its passphrase and the SAS aren't in this repository, and must never be.

## Where we are

| Step | State |
|---|---|
| Azure storage | ✅ created by hand from `infra/terraform/bootstrap` |
| Identities, `backup-sas` secret, failure alert | ✅ released as [`prod-2026-10-31.2`](https://github.com/SisyphusRex/cloud-computing-semester-project/releases/tag/prod-2026-10-31.2) |
| Upload credential | ✅ created; **expires 2027-10-31** |
| Backup CronJob and image | ✅ released as [`prod-2026-10-31.3`](https://github.com/SisyphusRex/cloud-computing-semester-project/releases/tag/prod-2026-10-31.3) |
| First backup and restore test | ✅ passed |
| Protections and alert | ✅ passed |
| First scheduled run (08:00 UTC) | ⬜ check on 2026-11-01 |
| Backup before `make cloud-pause` | ⬜ not tested on the real environment yet |

## Our environment

| What | Value |
|---|---|
| Resource group | `rg-li-backup`, `northcentralus` (Azure for Students) |
| Storage account | `libackupecd087147d` |
| Container | `https://libackupecd087147d.blob.core.windows.net/backups` |
| Retention | Immutable for 30 days (unlocked policy), deleted at 35 days |
| Google service account | `li-backup@lecture-indexer-511419.iam.gserviceaccount.com` |
| Upload credential | Secret Manager `backup-sas`, version 1 |
| Encryption public key | `age1zuvsq4vtwc49dwkdt8uknl3kh2z2rt52p8r3kmfag4n9a0kwz4sqes3nz2` |
| Schedule | Daily at 08:00 UTC, plus before each `make cloud-pause` |
| Alert | Cloud Monitoring policy "Database backup failed", by email |

## What we did

### 1. Checked the environment

We signed in with `az login` and `gcloud auth login`, set the project to `lecture-indexer-511419`, and ran `make cloud-status`. Cloud SQL was `ALWAYS`/`RUNNABLE` and both APIs were up, so nothing needed resuming.

### 2. Created the encryption key

```sh
age-keygen -o ~/li-backup.key
age-keygen -y ~/li-backup.key > ~/li-backup.pub
age -p -o ~/li-backup.key.age ~/li-backup.key
age -d ~/li-backup.key.age | diff - ~/li-backup.key && echo match
```

The team doesn't use a password manager, so the private key is protected by a passphrase, and `~/li-backup.key.age` is kept off the machine. We decided against committing that file, even encrypted: the repository is public, Git history can't be recalled, and a weak passphrase could be attacked offline forever.

### 3. Created the Azure storage

```sh
az provider register --namespace Microsoft.Storage
cd infra/terraform/bootstrap
terraform init -backend-config="bucket=lecture-indexer-511419-tfstate"
terraform plan
terraform apply
```

The first plan, using `azurerm_storage_account`, showed that the storage account's access keys would go into Terraform state, which CI's plan identity can read. Nothing had been applied yet, so we switched that one resource to the `azapi` provider. The new plan was `5 to add, 0 to change, 0 to destroy`, with no key attributes.

After the apply, we checked:

```sh
terraform state pull | grep -ciE 'access_?key|connection_?string'   # 0
az storage container immutability-policy show \
  --account-name libackupecd087147d --container-name backups \
  --query immutabilityPeriodSinceCreationInDays                     # 30
```

Azure for Students accepted every setting: Cool tier, LRS, TLS 1.2, HTTPS only, private access, shared-key access on.

### 4. Created the alert channel

The email address went straight to Google, so it's not in the repository, Terraform state or plan files. Terraform only receives the channel's name, through the `ALERT_NOTIFICATION_CHANNEL` GitHub variable.

```sh
gcloud beta monitoring channels create --type=email \
  --display-name="Lecture Indexer backups" \
  --channel-labels=email_address=<email> --format='value(name)'
gh variable set ALERT_NOTIFICATION_CHANNEL --body "<the name it printed>"
```

### 5. Released Phase 1: identities, secret and alert

Backups went out in two releases, because the second needed values from the first, and a release refuses to run while `REPLACE_ME` is in `values.env`.

We committed only `infra/terraform/` and the `TF_VAR_alert_notification_channel` lines in the two workflows, using `git add -p` for `release.yml`. That went in through [#2](https://github.com/SisyphusRex/cloud-computing-semester-project/pull/2) into `development` and [#3](https://github.com/SisyphusRex/cloud-computing-semester-project/pull/3) into `main`. The plan was `7 to add, 0 to change, 0 to destroy`, and the release finished as `prod-2026-10-31.2` at 17:41.

### 6. Created the upload credential

```sh
make cloud-backup-sas
gcloud secrets versions list backup-sas
```

This created version 1 of `backup-sas`, valid until 2027-10-31. It came before Phase 2 so that the job's secret would have a value to mount.

### 7. Released Phase 2: the backup job

We updated the branch from `development`, replaced the four `REPLACE_ME` values in `deploy/k8s/overlays/prod/values/values.env`, and confirmed the manifests rendered correctly with those values.

The change went in through [#4](https://github.com/SisyphusRex/cloud-computing-semester-project/pull/4). The **Backup image** CI job built and tested the image for the first time, and all its checks passed. The first release, through [#5](https://github.com/SisyphusRex/cloud-computing-semester-project/pull/5), [failed at step 4](https://github.com/SisyphusRex/cloud-computing-semester-project/actions/runs/41226862658) (see [Problems](#problems-we-hit)). After the fix in [#6](https://github.com/SisyphusRex/cloud-computing-semester-project/pull/6), the release through [#7](https://github.com/SisyphusRex/cloud-computing-semester-project/pull/7) [succeeded](https://github.com/SisyphusRex/cloud-computing-semester-project/actions/runs/41227650965) as `prod-2026-10-31.3`. The CronJob was deployed, and the API still answered.

### 8. Took the first backup

```sh
make cloud-backup
```

It produced `li-2026-10-31T181152Z.dump.age`, 22,713 bytes, with the job finishing in 9 seconds.

### 9. Tested a restore

```sh
make cloud-restore ARGS="list"
make cloud-restore ARGS="restore li-2026-10-31T181152Z.dump.age $HOME/li-backup.key"
```

The backup decrypted and restored into a temporary `li_restore` database on Cloud SQL. There were no row-count differences from `li` and no `pg_restore` errors. Afterwards the temporary job and database were gone, and `li` wasn't touched.

### 10. Checked the protections

| Check | Expected | Result |
|---|---|---|
| Read a blob with the SAS | Refused | `403` |
| List the container with the SAS | Refused | `403` |
| Overwrite a blob with the SAS | Refused | `403` |
| Delete a blob with the SAS | Refused | `403` |
| Delete a blob with the account key | Refused | `BlobImmutableDueToPolicy` |

### 11. Tested the failure alert

We pointed the CronJob at a database that doesn't exist, ran `make cloud-backup`, and put it back:

```sh
kubectl -n li patch cronjob backup --type=json -p '[{"op":"replace","path":"/spec/jobTemplate/spec/template/spec/containers/0/env/2/value","value":"no_such_database"}]'
make cloud-backup
kubectl -n li patch cronjob backup --type=json -p '[{"op":"replace","path":"/spec/jobTemplate/spec/template/spec/containers/0/env/2/value","value":"li"}]'
make cloud-backup
```

The job failed after its retries, and the "Database backup failed" email arrived at 18:17, as soon as the job gave up. The recovery backup, `li-2026-10-31T181709Z.dump.age`, succeeded, and we confirmed the CronJob pointed back at `li`.

## Problems we hit

| Problem | Cause | Fix |
|---|---|---|
| The account key would have been stored in Terraform state | `azurerm_storage_account` always saves the keys, and CI's plan identity can read the state bucket | Used the `azapi` provider for the account, before anything was applied |
| A GitHub secret for the alert email wouldn't have been private | Terraform would write it into the plan file, which is uploaded as a workflow artifact, and anyone signed in to GitHub can download those on a public repository | Terraform takes only the channel's name |
| A release with neither Terraform changes nor migrations failed at step 4 with `You do not currently have an active account selected` | `setup-gcloud` activates whatever credentials exist when it runs, and the sign-in before it is skipped for such a release. This was the first release of that kind since 2026-10-18, so the bug had never surfaced | `release.yml` runs `setup-gcloud` again after the deploy sign-in. Production wasn't affected, because the failure came before the rollout |
| `gh pr create --head development --fill` failed with `could not find any commits` | `--fill` reads the local `development` branch, which didn't have the merge made on GitHub | Used `--body` instead |
| `gcloud components install beta` failed | `gcloud` was installed from `apt`, which manages its own components | Not needed: the `apt` package already includes `beta` |
| `make cloud-status` ended with a `compute.googleapis.com` name resolution error | A brief network failure on the local machine, on the command's last check | Nothing to fix; the rest of the output was valid |

## Later changes

How to add teammates to the alert is now in the [backup runbook](../../runbooks/backup-and-restore.md#add-teammates-to-the-failure-alert). What was still open after this setup is in the [to-do list](../../todo.md).
