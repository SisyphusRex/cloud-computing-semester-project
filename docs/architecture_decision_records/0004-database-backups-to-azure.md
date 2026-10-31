# ADR 0004: Nightly encrypted database backups to Azure

- **Status:** Accepted
- **Date:** 2026-10-31
- **Changes:** where the backup storage lives in the [implementation plan](../implementation-plan.md), step 5 (`bootstrap`, not `envs/prod`), and how the SAS is created (a script, not Terraform)

## Context

Cloud SQL's automated backups are off to save cost, on the understanding that a nightly dump to Azure would replace them. Until now, that dump didn't exist. The only backups were the on-demand ones a release takes before migrating, and Cloud SQL deletes those with the instance.

Three things shaped the design:

- **`terraform destroy` on `envs/prod` is a normal way to stop paying** ([runbook](../runbooks/bootstrap.md)), and it deletes the database. Backups must survive it.
- **The environment is often paused,** and a paused database can't be backed up, so a nightly schedule alone could rarely fire.
- **The repository is public,** and read-only pull request plans can read Terraform state. Plan files are uploaded as workflow artifacts, which anyone signed in to GitHub can download on a public repository. So secrets can't be in state, and personal data can't be in plans.

## Decision

**A nightly CronJob dumps the database, encrypts it to a public key, and uploads it to Azure Blob Storage with a create-only credential. `make cloud-pause` takes a backup first.**

```
CronJob backup (08:00 UTC, Spot node)
  cloud-sql-proxy sidecar → pg_dump -Fc as li_admin → age, to a public key → PUT with a create-only SAS
```

| Choice | Decision | Why |
|---|---|---|
| Storage location | `infra/terraform/bootstrap`, resource group `rg-li-backup` | Outside `envs/prod`, so `terraform destroy` leaves it alone. CI never plans `bootstrap`, so CI's identities don't need access to it |
| Keeping the account key out of state | The storage account uses the `azapi` provider; everything else uses `azurerm` | `azurerm_storage_account` always copies the account keys into state, and CI's plan identity can read the state bucket. `azapi` stores only the settings it was given. The account key is fetched by `az` when it's needed |
| Storage settings | LRS, Cool tier; 30-day immutability on the container; lifecycle rule deletes blobs at 35 days | Cool suits data that's rarely read, and bills blobs for 30 days anyway. Immutability means nothing can alter or delete a backup, even with the account key |
| Immutability policy | Unlocked | Blocks changes the same way, but a subscription owner can remove it, so the project can still be torn down at the end of the semester. A locked policy can't be removed or shortened |
| Encryption | `age`, public key in `values.env`, private key offline | Neither Azure nor the cluster can read a backup. The public key is safe in a public repository |
| Upload credential | Container SAS with only create permission, in Secret Manager as `backup-sas` | A stolen SAS can't read, list, overwrite or delete. It needs no Azure role assignment, which CI's Contributor identity couldn't create |
| SAS creation | `make cloud-backup-sas`, outside Terraform | Terraform could only create it as a value kept in state. Terraform owns the empty secret and who can read it |
| Image | Separate `backup/` image: Alpine, `postgresql16-client`, `age`, `curl` | Small, with nothing unrelated in it |
| Non-secret settings | Written into the CronJob by Kustomize `replacements`, not read from `li-config` | `li-config` has no name hash, so a rollback to a tag from before backups replaces it without these keys. The CronJob stays deployed through such a rollback and must keep working |
| While paused | `make cloud-pause` takes a backup first and stops if it fails; the CronJob is suspended; `make cloud-resume` turns it back on | The latest data is always saved before the database stops, and a paused night isn't a failure. `SKIP_BACKUP=1` bypasses the backup |
| Failure alert | Cloud Monitoring alert on the Kubernetes events for a Job giving up; Terraform receives only the channel name | Catches any failure, including a killed pod that logged nothing. The email address is set when the channel is created, so it's never in the repository, in state, or in a plan artifact |
| Restore | `make cloud-restore`, on your own machine | The private key never enters the cluster. It restores into `li_restore` and compares row counts with `li` by default, so testing a restore is routine and safe |

## Alternatives considered

| Option | Why not |
|---|---|
| Turn on Cloud SQL automated backups | Simple, but they're deleted with the instance, stay in one cloud, and the plan is to keep this cost off |
| Keyless Azure access through workload identity federation | No secret to rotate, but it needs a custom role, since no built-in role is write-only, and role assignments CI can't create. A broader role could also read backups |
| Storage in `envs/prod` with `prevent_destroy` | Blocks `terraform destroy` for the whole environment, which is the cost control we want to keep |
| A locked immutability policy | Stronger, but nobody could remove it until the last blob expires, which would block teardown |
| GPG instead of `age` | Works, but needs a keyring and more setup for the same result |
| A GitHub secret holding the alert email | Keeps it out of logs, but Terraform would write it into the plan file, which is uploaded as an artifact |

## Consequences

- **Up to 24 hours of data can be lost,** less when a pause backup ran more recently. Releases with migrations still take their own Cloud SQL backup first.
- **Losing the private key loses every backup.** Nothing else can decrypt them, so it must be kept somewhere that survives this project's infrastructure, and be available to more than one person. It stays out of this public repository, even encrypted, because Git history can't be recalled.
- **The SAS expires after a year.** The next backup then fails and the alert fires. `make cloud-backup-sas` renews it.
- **A subscription owner can still remove the unlocked policy.** Immutability protects against a stolen SAS or a mistake, not against a compromised Azure owner account.
- **Backups log in as `li_admin`,** the same as migrations. The CronJob's Google service account can read that password. A read-only backup user is worth considering in the M3 security review.
- **The alert doesn't notice a Job that never starts,** such as when the schedule is suspended by mistake. `make cloud-status` shows the last successful backup, as a second check.
- **`make cloud-pause` takes longer,** by 1-5 minutes.
- **After `terraform destroy` and a re-create,** `backup-sas` is a new, empty secret: run `make cloud-backup-sas` before the next release.
