# Implementation plan

Living plan for building Lecture Indexer (LI) from the [Milestone 1 proposal](milestones/m1_project_proposal/CS6030_F26_ProjectProposal_LectureIndexer.pdf): where the work stands and what's left. Update the status table as work lands. The design and its decisions are in [architecture.md](architecture.md).

Last updated: 2026-10-31.

## Status

| Step | What | State |
|---|---|---|
| 1 | Move proposal into the docs tree (now `docs/milestones/m1_project_proposal/`), README, scaffold the tree | ✅ done (`c40b2b7`) |
| 2 | `db/migrations`, `services/` (li_common, ingest, search), Dockerfiles, docker-compose, Makefile | ✅ done (`73ed7d8`): 67 tests pass against Postgres 16 |
| 3 | Terraform: `infra/terraform/bootstrap`, then `envs/prod` | ✅ written and validated (mocked `terraform test` passes). Bootstrap applied 2026-10-18 (Azure in `northcentralus` after the region policy refused `eastus2`); GitHub variables and the `prod` environment set. `envs/prod` applied 2026-10-18. See [runbook](runbooks/bootstrap.md) |
| 4 | `deploy/k8s` (Kustomize), GitHub workflows, `frontend/` | ✅ done: first release `prod-2026-10-18.1` on 2026-10-18; end-to-end test passed in production ([first-deployment.md](milestones/m2_prototype_review/first-deployment.md)) |
| 5 | Backup CronJob + Azure storage, monitoring module, security review doc | partly done: backups and their failure alert ([ADR 0004](architecture_decision_records/0004-database-backups-to-azure.md)); the rest of monitoring and the security review doc are still to do |

| Milestone | Due | Needs |
|---|---|---|
| M2 Prototype Review | Week 10 | Initial deployment, CI/CD pipeline, basic functionality (steps 3–4) |
| M3 Technical Review | Week 12 | Monitoring, security review, documentation (step 5) |
| Final Demonstration | Week 14 | Live demo, architecture talk, cost analysis, AI-usage reflection, lessons learned |

## Open items

- **User administration (ADRs 0002 and 0003)** for the M3 security review: who can grant what (admins do everything on the Admin page except disable themselves or change their own admin flag; the first admin comes from `li-admin`, which needs the database-admin secret; a stolen admin session reaches the top tier), the `user_audit` trail and `user_claimed` / `sign_in_not_invited` log events, and that the admin endpoints live in the Ingest API so Search keeps its read-mostly database role. Human access to the database (Cloud SQL Studio as `li_admin`) and its rules: [security/database-access.md](security/database-access.md). Contract step for the next release: drop the empty `PROFESSOR_EMAILS` key from `values.env`, and revoke Search's `INSERT` on `users` (sign-in no longer creates rows).
- **YouTube scope.** The proposal says the professor's YouTube token is requested with a read-only scope, but `captions.list` and `captions.download` only accept `youtube.force-ssl`. The token is used for one request and never stored or logged. Correct this in the M3 security review.
- **Tooling.** Required tools and install steps for Linux and WSL2 are in [local-development.md](local-development.md); `make doctor` checks them.

## After that: deploy (needs billing)

Infrastructure is applied and `values.env` is filled in. The release runs through `release.yml` ([release process](release-process.md), [first deployment](milestones/m2_prototype_review/first-deployment.md)); `terraform.yml` only posts plans on pull requests.

**Monitoring inputs (for step 5).** The services already log these events as JSON, ready for log-based metrics:

| `event` | Fields |
|---|---|
| `http_request` | `service`, `method`, `route`, `status`, `latency_ms` |
| `youtube_api_call` | `method`, `status`, `quota_units` |
| `ingest_succeeded` / `ingest_failed` | `video_id`, `lecture_id`, `segments` / `reason` |

## Start database backups: steps to run

The backup code is written but uncommitted, in the working tree, and nothing is backing up until these steps are done ([ADR 0004](architecture_decision_records/0004-database-backups-to-azure.md)). It ships in two releases, because Phase 2 needs values that only exist after Phase 1, and a release refuses to run while `REPLACE_ME` is in `values.env`.

Run everything from the repository root unless a step says otherwise. Steps 1-13 take about an hour, mostly waiting for releases. Stop and fix anything that fails before moving on.

### Before you start

1. **Check the tools.** You need `gh`, `gcloud`, `kubectl`, `az`, `jq`, and `psql` and `pg_restore` 16 or newer:
   ```sh
   sudo apt install age                 # gives age and age-keygen
   gcloud beta monitoring channels create --help > /dev/null   # must work; apt installs of gcloud already include beta
   pg_restore --version
   ```
2. **Sign in, and start the environment if it's paused:**
   ```sh
   az login
   gcloud auth login
   gcloud config set project lecture-indexer-511419
   gh auth status
   make cloud-status
   make cloud-resume                    # only if Cloud SQL isn't ALWAYS/RUNNABLE
   ```

### Phase 1: storage, identities and the alert

3. **Create the encryption key,** in a folder outside this repository, and save encrypted copies off this machine:
   ```sh
   age-keygen -o ~/li-backup.key
   age-keygen -y ~/li-backup.key > ~/li-backup.pub      # the public key, for step 12
   age -p -o ~/li-backup.key.age ~/li-backup.key        # asks for a passphrase
   age -d ~/li-backup.key.age | diff - ~/li-backup.key && echo match
   ```
   Keep `~/li-backup.key.age` in at least two places off this machine, such as Google Drive and a USB stick, but never in this public repository. Give a teammate the file, and the passphrase separately. **Without the key, no backup can be read.** Keep `~/li-backup.key` for now: step 15 needs it.

4. **Create the Azure storage.** `terraform.tfvars` should already be in `infra/terraform/bootstrap/`:
   ```sh
   az provider register --namespace Microsoft.Storage
   cd infra/terraform/bootstrap
   terraform init -backend-config="bucket=lecture-indexer-511419-tfstate"
   terraform plan
   ```
   The plan must say `5 to add, 0 to change, 0 to destroy`: `rg-li-backup`, `azapi_resource.account`, a container, an immutability policy and a management policy. It must not contain any `access_key` lines. If it differs, stop. Otherwise:
   ```sh
   terraform apply
   terraform state pull | grep -ciE 'access_?key|connection_?string'   # must print 0
   cd ../../..
   az storage container immutability-policy show \
     --account-name libackupecd087147d --container-name backups \
     --query immutabilityPeriodSinceCreationInDays                     # must print 30
   ```
   A `RequestDisallowedByAzure` error means an Azure for Students policy refused a setting, so stop there.

5. **Create the alert email channel,** and give GitHub its name. Your email stays out of the repository:
   ```sh
   CHANNEL=$(gcloud beta monitoring channels create --type=email \
     --display-name="Lecture Indexer backups" \
     --channel-labels=email_address=YOUR_EMAIL \
     --format='value(name)')
   echo "$CHANNEL"                      # projects/.../notificationChannels/...
   gh variable set ALERT_NOTIFICATION_CHANNEL --body "$CHANNEL"
   ```

6. **Commit Phase 1 only.** `git add -p` shows each change in `release.yml`. Answer `y` to the `TF_VAR_alert_notification_channel` change, and `n` to the image build changes:
   ```sh
   git switch twp__db_backups           # your uncommitted changes come with you
   git add infra/terraform .github/workflows/terraform.yml
   git add -p .github/workflows/release.yml
   git diff --cached --stat             # only infra/terraform, including .terraform.lock.hcl, and the two workflow files
   git commit -m "Add backup storage, identities and failure alert"
   git push -u origin twp__db_backups
   ```

7. **Merge it into `development`:**
   ```sh
   gh pr create --base development --title "Add backup storage, identities and failure alert" --fill
   ```
   Wait for CI, and check the Terraform plan comment. It should add the `li-backup` service account, its IAM bindings, the `backup-sas` secret and the alert policy, and destroy nothing. Then merge the pull request.

8. **Release it.** Merge `development` into `main`, which starts a release:
   ```sh
   gh pr create --base main --head development --title "Release: backup infrastructure" --body "Releases what is on development."
   ```
   Merge it once CI passes, then open **Actions → Release**, read the review sheet and the plan, and approve. Wait for the run to finish.

9. **Create the upload credential.** Do this before step 13, or the backup job can't start:
   ```sh
   make cloud-backup-sas
   gcloud secrets versions list backup-sas     # one ENABLED version
   ```
   It prints when the credential expires. **Put that date in a calendar.**

### Phase 2: the backup job

10. **Update your branch:**
    ```sh
    git switch twp__db_backups
    git stash --include-untracked
    git fetch origin
    git rebase origin/development
    git stash pop
    ```

11. **Collect the four values:**
    ```sh
    cd infra/terraform/envs/prod
    terraform init -backend-config="bucket=lecture-indexer-511419-tfstate"
    terraform output -json workload_service_accounts | jq -r .backup
    echo "$(terraform output -raw backup_sas_secret)/versions/latest"
    cd ../../bootstrap
    terraform output -raw backup_container_url
    cd ../../..
    ```

12. **Replace the four `REPLACE_ME` values** in `deploy/k8s/overlays/prod/values/values.env`:

    | Key | Value |
    |---|---|
    | `BACKUP_GSA` | First line printed in step 11 |
    | `BACKUP_SAS_SECRET_VERSION` | Second line printed in step 11 |
    | `BACKUP_CONTAINER_URL` | Third line printed in step 11 |
    | `BACKUP_AGE_RECIPIENT` | The `age1...` public key: `cat ~/li-backup.pub` |

    These are all safe in a public repository. Then confirm none are left:
    ```sh
    grep -c REPLACE_ME deploy/k8s/overlays/prod/values/values.env   # must print 0
    ```

13. **Commit, merge and release the rest:**
    ```sh
    git add -A
    git status --short                  # no key files, nothing unexpected
    git commit -m "Back up the database to Azure nightly and before each pause"
    git push
    gh pr create --base development --title "Back up the database to Azure" --fill
    ```
    Wait for CI, and look at the **Backup image** job in particular: it's the first time the image is built and tested. Merge, then merge `development` into `main` as in step 8, and approve the release.

### Prove it works

14. **Take a backup:**
    ```sh
    make cloud-backup
    ```
    The output should end with a `backup_succeeded` line. Copy the `name`, which looks like `li-2026-11-01T150000Z.dump.age`.

15. **Restore it.** This is the real test, and it doesn't change `li`:
    ```sh
    make cloud-restore ARGS="list"
    make cloud-restore ARGS="restore BLOB_NAME_FROM_STEP_14 $HOME/li-backup.key"
    ```
    It should end with `Restore test finished`. If it fails with `pg_restore` errors or mismatched tables, backups aren't proven yet, so stop and investigate.

16. **Remove the local key.** First confirm an off-machine copy of `~/li-backup.key.age` still decrypts:
    ```sh
    age -d ~/li-backup.key.age | diff - ~/li-backup.key && echo match
    shred -u ~/li-backup.key
    ```
    For a later restore, recreate it with `age -d ~/li-backup.key.age > ~/li-backup.key`, and delete it again afterwards.

17. **Check the protections:** run all three checks in [Check the protections](runbooks/backup-and-restore.md#check-the-protections): the SAS is create-only, backups can't be deleted, and a forced failure sends the email. Put the CronJob back afterwards, as the runbook shows.

18. **Check pausing.** Run `make cloud-pause` and confirm it takes a backup first. Then run `make cloud-resume`, and `kubectl -n li get cronjob backup` should show `SUSPEND` as `False`.

19. **Next morning,** with the environment running overnight, run `make cloud-restore ARGS="list"` and confirm a backup from around 08:00 UTC is there. That proves the schedule, not just manual runs.

20. **Mark it done.** Delete this section, and record the date and restore result in the Status table.

Later problems and renewals are covered in the [backup runbook](runbooks/backup-and-restore.md).

## Remaining: step 5

- `modules/monitoring`: dashboard, log-based metrics, and the remaining alert policies (the backup alert is done).
- `docs/milestones/m3_technical_review/`, including the YouTube scope correction.

## Verification target

- `make lint`, `make test-db`, `make dev-up`, `make smoke`; `make frontend-test`; `make k8s-check`.
- `terraform -chdir=infra/terraform/envs/prod test` (no credentials), then `plan` against the real project; `make k8s-check`.
- CI green on a PR touching each top-level directory.
- End to end: sign in on the Cloud Run URL, register a captioned video, search a spoken term, and the link opens at the right second.
