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

The order matters. Backups need values from Terraform, and Kubernetes can't start the job until its secret has a value. So setup takes two releases: the second needs values that only exist after the first, and a release refuses to run while `REPLACE_ME` is in `values.env`. It takes about an hour, mostly waiting for releases. Run everything from the repository root, and stop and fix anything that fails before moving on. The [record of our setup](../milestones/m3_technical_review/azure-backup-setup.md) shows how this went in practice.

1. **Install the tools, and sign in.** `age` (`sudo apt install age`), plus `az`, `gcloud`, `kubectl` and `jq`, and `psql` and `pg_restore` 16 or newer. The alert channel needs `gcloud beta`; `apt` installs of `gcloud` already include it, and `gcloud components install beta` fails on them.
   ```sh
   gcloud beta monitoring channels create --help > /dev/null   # must work
   pg_restore --version
   az login
   gcloud auth login
   gcloud config set project <project>
   gh auth status
   make cloud-status
   make cloud-resume                    # only if Cloud SQL isn't ALWAYS/RUNNABLE
   ```
2. **Create the key pair,** in a folder outside this repository:
   ```sh
   age-keygen -o ~/li-backup.key
   age-keygen -y ~/li-backup.key > ~/li-backup.pub      # the public key (age1...), for step 7
   age -p -o ~/li-backup.key.age ~/li-backup.key        # asks for a passphrase
   age -d ~/li-backup.key.age | diff - ~/li-backup.key && echo match
   ```
   Keep the private key where it survives losing this machine: in a password manager if the team has one, or (what we do) `~/li-backup.key.age` in at least two places off this machine, such as Google Drive and a USB stick. Give a teammate the file, and the passphrase separately. **Without the key, no backup can be read.** Never commit it, even encrypted: this repository is public, Git history can't be recalled, and a weak passphrase could be attacked offline forever. Keep `~/li-backup.key` until step 9 needs it.
3. **Create the storage.** `terraform.tfvars` should already be in `infra/terraform/bootstrap/`:
   ```sh
   az provider register --namespace Microsoft.Storage
   cd infra/terraform/bootstrap
   terraform init -backend-config="bucket=<project>-tfstate"
   terraform plan
   ```
   On a project that's already bootstrapped, the plan must say `5 to add, 0 to change, 0 to destroy`: `rg-li-backup`, `azapi_resource.account`, a container, an immutability policy and a management policy. It must not contain any `access_key` lines. If it differs, stop. Otherwise:
   ```sh
   terraform apply
   terraform state pull | grep -ciE 'access_?key|connection_?string'   # must print 0
   terraform output backup_container_url
   cd ../../..
   az storage container immutability-policy show \
     --account-name <storage account> --container-name backups \
     --query immutabilityPeriodSinceCreationInDays                     # must print 30
   ```
   A `RequestDisallowedByAzure` error means an Azure for Students policy refused a setting, so stop there.
4. **Create the alert channel,** and keep your email out of the repository:
   ```sh
   gcloud beta monitoring channels create --type=email \
     --display-name="Backups" --channel-labels=email_address=<your email> \
     --format='value(name)'
   gh variable set ALERT_NOTIFICATION_CHANNEL --body "<the name it printed>"
   ```
5. **Release the Terraform changes.** This creates the `backup` service account, its IAM bindings, the empty `backup-sas` secret and the alert, and should destroy nothing. Wait for CI, check the Terraform plan comment on the pull request and the plan in the release run, and approve.
6. **Create the SAS,** before the next release, or the backup job can't start:
   ```sh
   make cloud-backup-sas
   gcloud secrets versions list backup-sas     # one ENABLED version
   ```
   It prints when the credential expires. **Put that date in a calendar.**
7. **Fill in `deploy/k8s/overlays/prod/values/values.env`,** then release. These values are all safe in a public repository.

   | Key | Value |
   |---|---|
   | `BACKUP_GSA` | `terraform output -json workload_service_accounts \| jq -r .backup` (in `envs/prod`) |
   | `BACKUP_SAS_SECRET_VERSION` | `terraform output -raw backup_sas_secret` (in `envs/prod`), plus `/versions/latest` |
   | `BACKUP_AGE_RECIPIENT` | The public key: `cat ~/li-backup.pub` |
   | `BACKUP_CONTAINER_URL` | The URL from step 3 |

   Confirm none are left, and that no key files are about to be committed:
   ```sh
   grep -c REPLACE_ME deploy/k8s/overlays/prod/values/values.env   # must print 0
   git status --short
   ```
   Look at the **Backup image** CI job in particular, then approve the release.
8. **Take a backup:** `make cloud-backup`. The output should end with a `backup_succeeded` line. Copy its `name`, which looks like `li-2026-11-01T150000Z.dump.age`.
9. **Run the [restore test](#test-a-restore)** with that name and `$HOME/li-backup.key`. It should end with `Restore test finished`. If it fails with `pg_restore` errors or mismatched tables, backups aren't proven yet, so stop and investigate.
10. **Remove the local key.** First confirm an off-machine copy still decrypts:
    ```sh
    age -d ~/li-backup.key.age | diff - ~/li-backup.key && echo match
    shred -u ~/li-backup.key
    ```
    For a later restore, recreate it with `age -d ~/li-backup.key.age > ~/li-backup.key`, and delete it again afterwards.
11. **[Check the protections](#check-the-protections).**
12. **Check pausing.** Run `make cloud-pause` and confirm it takes a backup first. Then run `make cloud-resume`, and `kubectl -n li get cronjob backup` should show `SUSPEND` as `False`.
13. **Next morning,** with the environment running overnight, run `make cloud-restore ARGS="list"` and confirm a backup from around 08:00 UTC is there. That proves the schedule, not just manual runs.

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

## Add teammates to the failure alert

The alert currently emails one address. Each person needs their own notification channel, and the alert has to list all of them. Terraform accepts only one channel so far, so this takes a small code change and a release. **Don't add people to the alert in the Cloud Console or with `gcloud`:** the next `terraform apply` would remove them again.

Keep teammates' email addresses out of this repository, which is public. The channel names below are safe to share.

1. **Create a channel for each teammate,** and save the `projects/.../notificationChannels/...` name each command prints. Google doesn't ask them to confirm, so tell them these emails are coming.
   ```sh
   gcloud beta monitoring channels create --type=email \
     --display-name="Backups - <name>" \
     --channel-labels=email_address=<email> \
     --format='value(name)'
   ```
2. **Change the Terraform.** In `infra/terraform/modules/monitoring/main.tf`, change the alert's channels to:
   ```hcl
   notification_channels = split(",", var.notification_channel)
   ```
   Then update the descriptions of `notification_channel` (in that module's `variables.tf`) and `alert_notification_channel` (in `envs/prod/variables.tf`) to say it's a comma-separated list. Empty still means no alert.
3. **Update the GitHub variable,** right before merging. Until the code change is live, the current code would treat the list as one invalid channel name. Use commas and no spaces:
   ```sh
   gh variable set ALERT_NOTIFICATION_CHANNEL \
     --body "projects/lecture-indexer-511419/notificationChannels/1402934230220833539,<teammate 1 channel>,<teammate 2 channel>"
   ```
4. **Release it.** Merge to `development`, then `main`, and approve. The plan should be `0 to add, 1 to change, 0 to destroy`, with the change on the alert policy.
5. **Test it.** Rerun the forced failure in [Check the protections](#check-the-protections), confirm that everyone got the email, and put the CronJob back.

**With a Google Group or mailing list,** you can skip the code change. Point the existing channel at the group, and manage who gets the email there. The group has to accept mail from outside addresses, so test this too:

```sh
gcloud beta monitoring channels update 1402934230220833539 \
  --update-channel-labels=email_address=<group email>
```

## Tearing down

`terraform destroy` on `envs/prod` leaves the backups in place. After a re-create, `backup-sas` is a new, empty secret, so run `make cloud-backup-sas` before releasing.

To delete the backups as well, at the end of the project, remove the immutability policy on the container in the Azure Portal, then delete `rg-li-backup`.
