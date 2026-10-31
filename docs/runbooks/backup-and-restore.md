# Backup and restore

How the production database is backed up to Azure, how to set that up, and how to get data back. The design and its limits are in [ADR 0004](../architecture_decision_records/0004-database-backups-to-azure.md), and the record of the original setup is in [azure-backup-setup.md](../milestones/m3_technical_review/azure-backup-setup.md).

| Command | What it does |
|---|---|
| `make cloud-status` | Includes the time of the last successful backup |
| `make cloud-backup` | Backs up now, and waits for it |
| `make cloud-pause` | Backs up, then pauses. `SKIP_BACKUP=1` skips the backup |
| `make cloud-restore ARGS="list"` | Lists the backups |
| `make cloud-restore ARGS="restore BLOB KEYFILE"` | Restores into `li_restore`, compares it with `li`, then drops it |
| `make cloud-restore ARGS="restore BLOB KEYFILE --overwrite"` | **Replaces the production database** |
| `make cloud-backup-sas` | Creates or renews the upload credential |

Backups run at 08:00 UTC, are named `li-<UTC time>.dump.age`, can't be changed or deleted for 30 days, and are deleted automatically at 35 days.

## First-time setup

The order matters. Backups need values from Terraform, and Kubernetes can't start the job until its secret has a value.

1. **Install the tools.** `age`, plus `az`, `gcloud`, `kubectl` and `jq`, and `psql` and `pg_restore` 16 or newer.
2. **Create the key pair,** on your own machine:
   ```sh
   age-keygen -o li-backup.key
   ```
   It prints the public key (`age1...`). Keep the private key where it survives losing this machine: a password manager, or `age -p -o li-backup.key.age li-backup.key` and that encrypted file in two places, such as Google Drive and a USB stick. Share it with a teammate, then delete the plain file. **Without it, no backup can be read.** Never commit it, even encrypted: this repository is public.
3. **Create the storage:**
   ```sh
   terraform -chdir=infra/terraform/bootstrap init -backend-config="bucket=<project>-tfstate"
   terraform -chdir=infra/terraform/bootstrap apply
   terraform -chdir=infra/terraform/bootstrap output backup_container_url
   ```
4. **Create the alert channel,** and keep your email out of the repository:
   ```sh
   gcloud beta monitoring channels create --type=email \
     --display-name="Backups" --channel-labels=email_address=<your email> \
     --format='value(name)'
   gh variable set ALERT_NOTIFICATION_CHANNEL --body "<the name it printed>"
   ```
5. **Release the Terraform changes.** This creates the `backup` service account, the empty `backup-sas` secret and the alert.
6. **Create the SAS:** `make cloud-backup-sas`.
7. **Fill in `deploy/k8s/overlays/prod/values/values.env`,** then release. The release refuses to run while any `REPLACE_ME` remains.

   | Key | Value |
   |---|---|
   | `BACKUP_GSA` | `backup` in `terraform output workload_service_accounts` (in `envs/prod`) |
   | `BACKUP_SAS_SECRET_VERSION` | `terraform output -raw backup_sas_secret` (in `envs/prod`), plus `/versions/latest` |
   | `BACKUP_AGE_RECIPIENT` | The public key from step 2 |
   | `BACKUP_CONTAINER_URL` | The URL from step 3 |
8. **Test it:** run `make cloud-backup`, then the restore test below, then [check the SAS and the alert](#check-the-protections).

## Test a restore

**A backup that has never been restored isn't proven.** Do this after setup, and again after any change to the schema or to backups. It doesn't change `li`.

```sh
make cloud-restore ARGS="list"
make cloud-restore ARGS="restore li-2026-11-01T080000Z.dump.age /path/to/li-backup.key"
```

It prints any differences in row counts between `li` and the backup. Rows written since the backup are expected to differ. It fails, and leaves `li_restore` in place, if the tables don't match.

## Restore production

**This overwrites everything in `li`. Anything written since the backup is lost.** If you can, take a fresh backup first with `make cloud-backup`, and test the backup you're about to use.

1. Stop the APIs, so nothing writes during the restore:
   ```sh
   kubectl -n li scale deploy/ingest deploy/search --replicas=0
   ```
2. Restore. It asks you to type `overwrite li`:
   ```sh
   make cloud-restore ARGS="restore <blob> /path/to/li-backup.key --overwrite"
   ```
3. Start the APIs again, and check the app:
   ```sh
   kubectl -n li scale deploy/ingest deploy/search --replicas=1
   ```

**On a new instance,** after `terraform destroy` and a re-create, run a release first. It creates the schema and the group roles that the backup's grants refer to. Then restore as above.

**Without the cluster,** you can still read a backup. Download the blob in the Azure Portal (`rg-li-backup`), then:

```sh
age --decrypt -i li-backup.key -o li.dump <blob>
pg_restore --no-owner -d <local database> li.dump
```

The `li_ingest_role` and `li_search_role` grants fail with errors unless those roles exist. The data still restores. Delete `li.dump` when you're done: it isn't encrypted.

## When the alert fires

1. Find out why: `kubectl -n li get jobs -l app.kubernetes.io/name=backup`, then `kubectl -n li logs job/<name> -c backup`. The job logs `backup_succeeded` or `backup_failed`.
2. Fix it, then run `make cloud-backup`.

| What you see | Cause | Fix |
|---|---|---|
| `curl: (22) ... error: 403` | The SAS expired or was replaced | `make cloud-backup-sas` |
| Pod stuck in `ContainerCreating`, mount errors | `backup-sas` has no version, or the `values.env` path is wrong | `make cloud-backup-sas`; check `BACKUP_SAS_SECRET_VERSION` |
| `pg_dump: error: connection ...` | Cloud SQL is stopped or still starting | `make cloud-status`; resume, and wait |
| `pg_dump: error: ... server version` | Cloud SQL was upgraded past the client | Update `postgresql16-client` in `backup/Dockerfile` |
| `DeadlineExceeded` | The dump took over 30 minutes | Raise `activeDeadlineSeconds` in `deploy/k8s/base/backup/cronjob.yaml`, and check the 1 Gi `emptyDir` limit |

## Renew the SAS

It lasts a year. `make cloud-backup-sas` prints the expiry date, so put it in a calendar. Running it again adds a new version of the secret, and the next backup uses it.

To cancel a leaked SAS at once, rotate the storage account's key in the Azure Portal, then run `make cloud-backup-sas`. A leaked SAS can only add blobs, so the risk is junk files, not lost or exposed backups.

## Check the protections

Run these once after setup, with your own Azure login (the Terraform output has the URL).

- **The SAS is create-only.** Using the value of the `backup-sas` secret, reading (`curl "$URL/<blob>?$SAS"`), overwriting and listing must all return 403.
- **Backups are immutable.** `az storage blob delete` on a recent blob must fail, even with the account key.
- **The alert fires.** Force a failure, then undo it:
  ```sh
  kubectl -n li patch cronjob backup --type=json -p '[{"op":"replace","path":"/spec/jobTemplate/spec/template/spec/containers/0/env/2/value","value":"no_such_database"}]'
  make cloud-backup   # fails; the email arrives within a few minutes
  kubectl -n li patch cronjob backup --type=json -p '[{"op":"replace","path":"/spec/jobTemplate/spec/template/spec/containers/0/env/2/value","value":"li"}]'
  ```

## Tearing down

`terraform destroy` on `envs/prod` leaves the backups in place. After a re-create, `backup-sas` is a new, empty secret, so run `make cloud-backup-sas` before releasing.

To delete the backups as well, at the end of the project, remove the immutability policy on the container in the Azure Portal, then delete `rg-li-backup`.
