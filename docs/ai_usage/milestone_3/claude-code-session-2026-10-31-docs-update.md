# AI usage log: Claude Code session, 2026-10-31 (documentation update)

| | |
|---|---|
| Tool | Claude Code (VS Code extension), model Claude Opus 5.5 |
| User | Theodore Podewil |
| Date | 2026-10-31 |
| Branch | `twp__update_docs`; not pushed or merged in this session |
| Commits produced | `2a3d6af`, `64db4af`, `fe8c296`, `20bf79e`, `9bc3d60`, `e4ee744`, plus the commit adding this log |
| Outcome | Every link and repository path in the docs resolves, stale facts are corrected against the code, and each kind of fact has one home. `make docs-check` keeps it that way in CI. An audit of 2,399 baseline text units left none unaccounted for. Start at the [documentation map](../../README.md) |

Each entry gives the prompt exactly as typed, then a summary of what Claude did in response.

---

## 1. Plan the update

> come up with a plan to update the documentation.  We do not want to lose any detail, but links may be stale and info may be scattered.

Working in plan mode, Claude read all the live docs itself rather than summarizing them, since losing detail was the main risk. A script checked every link and backticked path, and Claude fetched each external URL and looked up every PR, release and run through `gh`.

The external links were all good. The internal ones weren't: `docs/implementation-plan.md` had moved into the milestone folder and back, leaving 23 broken links in live docs and 2 in session logs. Claude then compared the docs' claims with the code, which found problems no link check could. For example, the real Google test still set `PROFESSOR_EMAILS`, which nothing reads, and `create-admin` alone wouldn't have let the tester open **Manage**.

The plan split the 448-line implementation plan by purpose, kept dated records as records, and required a ledger proving nothing was dropped. The user approved it.

## 2. Implementation

Claude worked in one commit per phase, so moves and edits could be reviewed separately:

| Commit | Phase |
|---|---|
| `2a3d6af` | Fixed the links, and added `scripts/check-docs.py`, `make docs-check` and a CI job. Claude confirmed the check fails on a broken link, anchor and path |
| `64db4af` | Corrected stale facts in place, after reading `release.yml` and the scripts. For example, every release runs the migrate Job, so the runbook's advice to re-run the deploy after rotating the password was obsolete |
| `fe8c296` | Moved sections verbatim by script: `architecture.md`, `runbooks/real-google-test.md`, the CI section of the release process. `azure-backup-setup.md` moved to the M3 folder with `git mv` |
| `20bf79e` | Merged duplicates, reconciled the three backup setup procedures, added banners to records, and collected the M3 notes in `security/review-notes.md` |
| `9bc3d60` | Added `docs/README.md` and `docs/onboarding.md` |

The checker first failed on two stock lines in `.gitignore`, and on new files that weren't tracked yet. Claude fixed both in the script.

## 3. Audit

A script split the baseline docs at `b69aeb0` into 2,399 units (sentences, table cells, list items, code lines) and searched for each in the final tree. 2,200 matched verbatim.

Claude read the other 199. Three were real gaps, which `e4ee744` restored: the $40–60 and $9 monthly cost totals, the `gh pr create` command for release pull requests, and checking the plan comment on the pull request. Claude also corrected one line the rules had wrongly marked as removed. The ledger below records the outcome of all 199.

Still unverified at the end of the session:

- `make dev-up` and `make smoke`, and the new `docker compose run` invite command in the real Google test, because this machine's Docker needs a `sudo` password. From reading the code, `li-admin` needs only `DATABASE_URL`, so the command should work without the override file's `-f` flags.
- `make k8s-check`, because `kustomize` isn't installed here. No manifests changed.
- The console links, which need a sign-in. Only their URLs were checked.
- The onboarding guide, which hasn't been followed by someone new. That's in the to-do list.

The remaining alerts and dashboard, and the contract-step code changes, were out of scope.

## 4. The first CI run

> commit and push

> i merged and pushed development

The working tree was already clean, so Claude pushed the 7 commits. After the user merged them, Claude checked CI on `development`. Seven jobs passed, including the Kubernetes and compose checks it couldn't run locally, but the new **Document links** job failed on `frontend/node_modules`.

The bug was in Claude's checker. `.gitignore` has `node_modules/`, which only matches a directory, and a fresh checkout doesn't have one. The check had only ever run on a machine where the directory existed. Claude reproduced the failure in a clean clone, and its first fix failed there too, because `git check-ignore -q` takes one path. The final fix passed in a clean clone, and a broken path still failed.

<details>
<summary>Ledger: the 199 baseline units not found verbatim</summary>

| Baseline line | Text | Outcome | Where |
|---|---|---|---|
| README.md:19 | Full rationale: | Corrected | root README |
| README.md:45 | Registering a lecture needs real Google sign-in, because the Ingest API calls YouTube with your token; see ... | Corrected | root README |
| README.md:59 | ci.yml (lint, tests, image builds, manifest and Terraform checks); deploy workflows come with the first dep... | Corrected | root README |
| README.md:60 | Dev and cost-control helpers | Corrected | root README |
| README.md:61 | Proposal, implementation plan, architecture decision records (ADRs), runbooks, security notes (e.g. databas... | Corrected | root README |
| azure-backup-setup.md:181 | **Test it.** Rerun the forced failure in step 11, confirm that everyone got the email, and put the CronJob ... | Moved | backup runbook |
| azure-backup-setup.md:198 | Remove the "Start database backups: steps to run" section from the implementation plan, and record the resu... | Done | this work removed the section it asked for |
| implementation-plan.md:3 | Update the status table and decisions as work lands. | Moved | architecture.md |
| implementation-plan.md:11 | Move proposal into docs/proposal/, README, scaffold the tree | Corrected | implementation-plan.md |
| implementation-plan.md:15 | partly done: backups and their failure alert (ADR 0004); the rest of monitoring and the security review doc... | Corrected | implementation-plan.md |
| implementation-plan.md:31 | Artifact Registry, Secret Manager + Workload Identity, Cloud Monitoring dashboard and alerts. | Corrected | architecture.md |
| implementation-plan.md:48 | **Database privileges via group roles**: li_ingest_role (read/write), li_search_role (read, plus creating u... | Corrected | architecture.md |
| implementation-plan.md:52 | **Powerful CI identities only in the prod GitHub environment** (github-terraform, github-deploy, id-li-gith... | Corrected | architecture.md |
| implementation-plan.md:52 | Bindings match the token's exact subject (repo:…:environment:prod vs repo:…:pull_request), so a workflow on... | Corrected | architecture.md |
| implementation-plan.md:67 | **Professor detection**: the frontend calls GET /ingest/courses; 403 means student | Corrected | architecture.md |
| implementation-plan.md:67 | No extra endpoint needed; roles stay server-side. | Corrected | architecture.md |
| implementation-plan.md:73 | Base for the next review sheet (make release-diff), rollback target, record of what ran when. Every release... | Corrected | architecture.md |
| implementation-plan.md:77 | The subscription may only deploy to canadacentral, mexicocentral, northcentralus, francecentral and swedenc... | Corrected | architecture.md |
| implementation-plan.md:85 | security/database-access.md. | Moved | security/review-notes.md; contract step already in todo.md |
| implementation-plan.md:85 | Contract step for the next release: drop the empty PROFESSOR_EMAILS key from values.env, and revoke Search'... | Moved | security/review-notes.md; contract step already in todo.md |
| implementation-plan.md:87 | **Not yet verified:** calls to the real YouTube API and real Google ID tokens (tests mock both); the next s... | Removed | resolved: done 2026-10-18; cost totals kept in the runbook |
| implementation-plan.md:87 | docker build and the compose stack are verified by the compose job in ci.yml on the first push. | Removed | resolved: done 2026-10-18; cost totals kept in the runbook |
| implementation-plan.md:88 | **Infrastructure not applied.** Someone with Owner on both clouds follows runbooks/bootstrap.md: state buck... | Removed | resolved: done 2026-10-18; cost totals kept in the runbook |
| implementation-plan.md:88 | It needs gcloud and az. | Removed | resolved: done 2026-10-18; cost totals kept in the runbook |
| implementation-plan.md:88 | Provisioning starts billing (roughly $40–60/month while running; see the runbook's cost table), so apply cl... | Removed | resolved: done 2026-10-18; cost totals kept in the runbook |
| implementation-plan.md:88 | Between test sessions, make cloud-pause / make cloud-resume cut idle cost to ~$9/month without changing the... | Removed | resolved: done 2026-10-18; cost totals kept in the runbook |
| implementation-plan.md:89 | **Tooling.** Required tools and install steps for Linux and WSL2 are in local-development.md; | Removed | pointer only: local-development.md and onboarding.md |
| implementation-plan.md:89 | make doctor checks them. | Removed | pointer only: local-development.md and onboarding.md |
| implementation-plan.md:91 | Done: step 3, Terraform | Moved | heading or wording changed; content in its new home |
| implementation-plan.md:111 | Step 4 so far: everything that doesn't need the cloud | Moved | heading or wording changed; content in its new home |
| implementation-plan.md:113 | **CI (.github/workflows/ci.yml)**, on pushes to main/development and on PRs, with no cloud credentials: | Moved | heading or wording changed; content in its new home |
| implementation-plan.md:124 | **Kubernetes (deploy/k8s)** | Moved | heading or wording changed; content in its new home |
| implementation-plan.md:136 | **Frontend (frontend/)**: | Moved | heading or wording changed; content in its new home |
| implementation-plan.md:136 | React app with Google sign-in (or dev sign-in with VITE_DEV_AUTH=1), course list, course search with timest... | Moved | heading or wording changed; content in its new home |
| implementation-plan.md:136 | Run it with make frontend-dev against the local APIs. 16 vitest tests cover the API client, excerpt renderi... | Moved | heading or wording changed; content in its new home |
| implementation-plan.md:138 | Next: real Google/YouTube test (free, before deploying) | Moved | heading or wording changed; content in its new home |
| implementation-plan.md:147 | Google Cloud Console (once) | Moved | heading or wording changed; content in its new home |
| implementation-plan.md:149 | Do this in the GCP project Terraform will use. | Merged | bootstrap.md step 5; test-specific notes in real-google-test.md |
| implementation-plan.md:149 | Terraform can't create the client (runbook step 5). | Merged | bootstrap.md step 5; test-specific notes in real-google-test.md |
| implementation-plan.md:151 | **APIs & Services → Library**: enable **YouTube Data API v3**. | Merged | bootstrap.md step 5; test-specific notes in real-google-test.md |
| implementation-plan.md:154 | openid, email, profile, https://www.googleapis.com/auth/youtube.force-ssl. | Merged | bootstrap.md step 5; test-specific notes in real-google-test.md |
| implementation-plan.md:155 | **Test users**: add every tester's Google account. | Merged | bootstrap.md step 5; test-specific notes in real-google-test.md |
| implementation-plan.md:156 | **Credentials → Create credentials → OAuth client ID**: | Merged | bootstrap.md step 5; test-specific notes in real-google-test.md |
| implementation-plan.md:157 | Type **Web application**. | Merged | bootstrap.md step 5; test-specific notes in real-google-test.md |
| implementation-plan.md:158 | Authorized JavaScript origin http://localhost:5173. | Merged | bootstrap.md step 5; test-specific notes in real-google-test.md |
| implementation-plan.md:163 | The override docker-compose.google.yml (in the repo root) turns it off for migrate, ingest and search, and ... | Corrected | real-google-test.md: invite-only sign-in |
| implementation-plan.md:163 | Create .env in the repo root; it's git-ignored, and Compose reads it itself, so the values also work under ... | Corrected | real-google-test.md: invite-only sign-in |
| implementation-plan.md:167 | PROFESSOR_EMAILS=&lt;your Google email> | Corrected | real-google-test.md: invite-only sign-in |
| implementation-plan.md:197 | The page loads. A student view means your email isn't in PROFESSOR_EMAILS. | Corrected | real-google-test.md: invite-only sign-in |
| implementation-plan.md:222 | The account owns the video but captions.download refused the auto-generated track. See "Record" below. If t... | Corrected | real-google-test.md: invite-only sign-in |
| implementation-plan.md:255 | After that: deploy (needs billing) | Moved | heading or wording changed; content in its new home |
| implementation-plan.md:257 | Infrastructure is applied and values.env is filled in. | Removed | duplicate of release-process.md and services/README.md |
| implementation-plan.md:257 | The release runs through release.yml (release process, first deployment); | Removed | duplicate of release-process.md and services/README.md |
| implementation-plan.md:257 | terraform.yml only posts plans on pull requests. | Removed | duplicate of release-process.md and services/README.md |
| implementation-plan.md:259 | **Monitoring inputs (for step 5).** The services already log these events as JSON, ready for log-based metr... | Removed | duplicate of release-process.md and services/README.md |
| implementation-plan.md:267 | Start database backups: steps to run | Moved | heading or wording changed; content in its new home |
| implementation-plan.md:269 | The backup code is written but uncommitted, in the working tree, and nothing is backing up until these step... | Corrected | backup runbook: two-release reason kept; "uncommitted" is obsolete |
| implementation-plan.md:269 | It ships in two releases, because Phase 2 needs values that only exist after Phase 1, and a release refuses... | Corrected | backup runbook: two-release reason kept; "uncommitted" is obsolete |
| implementation-plan.md:271 | Run everything from the repository root unless a step says otherwise. | Merged | backup runbook; one-time values in Environment and dashboard links |
| implementation-plan.md:271 | Steps 1-13 take about an hour, mostly waiting for releases. | Merged | backup runbook; one-time values in Environment and dashboard links |
| implementation-plan.md:275 | **Check the tools.** You need gh, gcloud, kubectl, az, jq, and psql and pg_restore 16 or newer: | Merged | backup runbook; one-time values in Environment and dashboard links |
| implementation-plan.md:277 | sudo apt install age                 # gives age and age-keygen | Merged | backup runbook; one-time values in Environment and dashboard links |
| implementation-plan.md:278 | gcloud beta monitoring channels create --help > /dev/null   # must work; apt installs of gcloud already inc... | Merged | backup runbook; one-time values in Environment and dashboard links |
| implementation-plan.md:281 | **Sign in, and start the environment if it's paused:** | Merged | backup runbook; one-time values in Environment and dashboard links |
| implementation-plan.md:285 | gcloud config set project lecture-indexer-511419 | Merged | backup runbook; one-time values in Environment and dashboard links |
| implementation-plan.md:291 | Phase 1: storage, identities and the alert | Moved | heading or wording changed; content in its new home |
| implementation-plan.md:293 | **Create the encryption key,** in a folder outside this repository, and save encrypted copies off this mach... | Merged | backup runbook; one-time values in Environment and dashboard links |
| implementation-plan.md:296 | age-keygen -y ~/li-backup.key > ~/li-backup.pub      # the public key, for step 12 | Merged | backup runbook; one-time values in Environment and dashboard links |
| implementation-plan.md:300 | Keep ~/li-backup.key.age in at least two places off this machine, such as Google Drive and a USB stick, but... | Merged | backup runbook; one-time values in Environment and dashboard links |
| implementation-plan.md:300 | **Without the key, no backup can be read.** Keep ~/li-backup.key for now: step 15 needs it. | Merged | backup runbook; one-time values in Environment and dashboard links |
| implementation-plan.md:302 | **Create the Azure storage.** terraform.tfvars should already be in infra/terraform/bootstrap/: | Merged | backup runbook; one-time values in Environment and dashboard links |
| implementation-plan.md:320 | **Create the alert email channel,** and give GitHub its name. | Merged | backup runbook; one-time values in Environment and dashboard links |
| implementation-plan.md:320 | Your email stays out of the repository: | Merged | backup runbook; one-time values in Environment and dashboard links |
| implementation-plan.md:322 | CHANNEL=$(gcloud beta monitoring channels create --type=email \ | Merged | backup runbook; one-time values in Environment and dashboard links |
| implementation-plan.md:324 | --channel-labels=email_address=YOUR_EMAIL \ | Merged | backup runbook; one-time values in Environment and dashboard links |
| implementation-plan.md:326 | echo "$CHANNEL"                      # projects/.../notificationChannels/... | Merged | backup runbook; one-time values in Environment and dashboard links |
| implementation-plan.md:327 | gh variable set ALERT_NOTIFICATION_CHANNEL --body "$CHANNEL" | Merged | backup runbook; one-time values in Environment and dashboard links |
| implementation-plan.md:330 | **Commit Phase 1 only.** git add -p shows each change in release.yml. | Removed | one-time branch handling; what happened is in azure-backup-setup.md |
| implementation-plan.md:330 | Answer y to the TF_VAR_alert_notification_channel change, and n to the image build changes: | Removed | one-time branch handling; what happened is in azure-backup-setup.md |
| implementation-plan.md:332 | git switch twp__db_backups           # your uncommitted changes come with you | Removed | one-time branch handling; what happened is in azure-backup-setup.md |
| implementation-plan.md:333 | git add infra/terraform .github/workflows/terraform.yml | Removed | one-time branch handling; what happened is in azure-backup-setup.md |
| implementation-plan.md:334 | git add -p .github/workflows/release.yml | Removed | one-time branch handling; what happened is in azure-backup-setup.md |
| implementation-plan.md:335 | git diff --cached --stat             # only infra/terraform, including .terraform.lock.hcl, and the two wor... | Removed | one-time branch handling; what happened is in azure-backup-setup.md |
| implementation-plan.md:336 | git commit -m "Add backup storage, identities and failure alert" | Removed | one-time branch handling; what happened is in azure-backup-setup.md |
| implementation-plan.md:337 | git push -u origin twp__db_backups | Removed | one-time branch handling; what happened is in azure-backup-setup.md |
| implementation-plan.md:340 | **Merge it into development:** | Removed | one-time branch handling; what happened is in azure-backup-setup.md |
| implementation-plan.md:342 | gh pr create --base development --title "Add backup storage, identities and failure alert" --fill | Removed | one-time branch handling; what happened is in azure-backup-setup.md |
| implementation-plan.md:344 | Wait for CI, and check the Terraform plan comment. | Merged | backup runbook; one-time values in Environment and dashboard links |
| implementation-plan.md:344 | It should add the li-backup service account, its IAM bindings, the backup-sas secret and the alert policy, ... | Merged | backup runbook; one-time values in Environment and dashboard links |
| implementation-plan.md:344 | Then merge the pull request. | Merged | backup runbook; one-time values in Environment and dashboard links |
| implementation-plan.md:346 | **Release it.** Merge development into main, which starts a release: | Merged | backup runbook; one-time values in Environment and dashboard links |
| implementation-plan.md:348 | gh pr create --base main --head development --title "Release: backup infrastructure" --body "Releases what ... | Merged | backup runbook; one-time values in Environment and dashboard links |
| implementation-plan.md:350 | Merge it once CI passes, then open **Actions → Release**, read the review sheet and the plan, and approve. | Merged | backup runbook; one-time values in Environment and dashboard links |
| implementation-plan.md:350 | Wait for the run to finish. | Merged | backup runbook; one-time values in Environment and dashboard links |
| implementation-plan.md:352 | **Create the upload credential.** Do this before step 13, or the backup job can't start: | Merged | backup runbook; one-time values in Environment and dashboard links |
| implementation-plan.md:361 | **Update your branch:** | Removed | one-time branch handling; what happened is in azure-backup-setup.md |
| implementation-plan.md:363 | git switch twp__db_backups | Removed | one-time branch handling; what happened is in azure-backup-setup.md |
| implementation-plan.md:364 | git stash --include-untracked | Removed | one-time branch handling; what happened is in azure-backup-setup.md |
| implementation-plan.md:365 | git fetch origin | Removed | one-time branch handling; what happened is in azure-backup-setup.md |
| implementation-plan.md:366 | git rebase origin/development | Removed | one-time branch handling; what happened is in azure-backup-setup.md |
| implementation-plan.md:367 | git stash pop | Removed | one-time branch handling; what happened is in azure-backup-setup.md |
| implementation-plan.md:370 | **Collect the four values:** | Merged | backup runbook; one-time values in Environment and dashboard links |
| implementation-plan.md:375 | echo "$(terraform output -raw backup_sas_secret)/versions/latest" | Merged | backup runbook; one-time values in Environment and dashboard links |
| implementation-plan.md:376 | cd ../../bootstrap | Merged | backup runbook; one-time values in Environment and dashboard links |
| implementation-plan.md:377 | terraform output -raw backup_container_url | Merged | backup runbook; one-time values in Environment and dashboard links |
| implementation-plan.md:381 | **Replace the four REPLACE_ME values** in deploy/k8s/overlays/prod/values/values.env: | Merged | backup runbook; one-time values in Environment and dashboard links |
| implementation-plan.md:385 | First line printed in step 11 | Merged | backup runbook; one-time values in Environment and dashboard links |
| implementation-plan.md:386 | Second line printed in step 11 | Merged | backup runbook; one-time values in Environment and dashboard links |
| implementation-plan.md:387 | Third line printed in step 11 | Merged | backup runbook; one-time values in Environment and dashboard links |
| implementation-plan.md:388 | The age1... public key: cat ~/li-backup.pub | Merged | backup runbook; one-time values in Environment and dashboard links |
| implementation-plan.md:390 | These are all safe in a public repository. | Merged | backup runbook; one-time values in Environment and dashboard links |
| implementation-plan.md:390 | Then confirm none are left: | Merged | backup runbook; one-time values in Environment and dashboard links |
| implementation-plan.md:395 | **Commit, merge and release the rest:** | Removed | one-time branch handling; what happened is in azure-backup-setup.md |
| implementation-plan.md:398 | git status --short                  # no key files, nothing unexpected | Merged | backup runbook; one-time values in Environment and dashboard links |
| implementation-plan.md:399 | git commit -m "Back up the database to Azure nightly and before each pause" | Removed | one-time branch handling; what happened is in azure-backup-setup.md |
| implementation-plan.md:401 | gh pr create --base development --title "Back up the database to Azure" --fill | Removed | one-time branch handling; what happened is in azure-backup-setup.md |
| implementation-plan.md:403 | Wait for CI, and look at the **Backup image** job in particular: it's the first time the image is built and... | Merged | backup runbook; one-time values in Environment and dashboard links |
| implementation-plan.md:403 | Merge, then merge development into main as in step 8, and approve the release. | Merged | backup runbook; one-time values in Environment and dashboard links |
| implementation-plan.md:405 | Prove it works | Moved | heading or wording changed; content in its new home |
| implementation-plan.md:411 | Copy the name, which looks like li-2026-11-01T150000Z.dump.age. | Merged | backup runbook; one-time values in Environment and dashboard links |
| implementation-plan.md:413 | **Restore it.** This is the real test, and it doesn't change li: | Merged | backup runbook; one-time values in Environment and dashboard links |
| implementation-plan.md:416 | make cloud-restore ARGS="restore BLOB_NAME_FROM_STEP_14 $HOME/li-backup.key" | Merged | backup runbook; one-time values in Environment and dashboard links |
| implementation-plan.md:420 | **Remove the local key.** First confirm an off-machine copy of ~/li-backup.key.age still decrypts: | Merged | backup runbook; one-time values in Environment and dashboard links |
| implementation-plan.md:427 | **Check the protections:** run all three checks in Check the protections: the SAS is create-only, backups c... | Merged | backup runbook; one-time values in Environment and dashboard links |
| implementation-plan.md:427 | Put the CronJob back afterwards, as the runbook shows. | Merged | backup runbook; one-time values in Environment and dashboard links |
| implementation-plan.md:433 | **Mark it done.** Delete this section, and record the date and restore result in the Status table. | Merged | backup runbook; one-time values in Environment and dashboard links |
| implementation-plan.md:435 | Later problems and renewals are covered in the backup runbook. | Merged | backup runbook; one-time values in Environment and dashboard links |
| implementation-plan.md:440 | docs/milestones/m3-technical-review.md, including the YouTube scope correction. | Corrected | implementation-plan.md |
| local-development.md:26 | gcloud, kubectl and gke-gcloud-auth-plugin are needed only to pause and resume the deployed environment (In... | Corrected | local-development.md |
| local-development.md:68 | Linux](#install-prerequisites-linux), skipping the Docker Engine install if you use Docker Desktop. | Corrected | local-development.md |
| local-development.md:76 | Only for make cloud-status, cloud-pause and cloud-resume, which pause and resume the deployed environment b... | Corrected | local-development.md |
| local-development.md:76 | On Ubuntu, Debian or WSL2, all three come from Google's apt repository: | Corrected | local-development.md |
| local-development.md:143 | That's described in the implementation plan, Next: real Google/YouTube test. | Corrected | local-development.md |
| monitoring/dashboard-links.md:3 | The monitoring dashboard and alerts from step 5 of the implementation plan will be added here once they exist. | Corrected | dashboard-links.md |
| monitoring/dashboard-links.md:19 | ingest, search, the migrate Job (filter by namespace li) | Corrected | dashboard-links.md |
| monitoring/dashboard-links.md:23 | Repository li: ingest, search, frontend, tagged by commit SHA | Corrected | dashboard-links.md |
| runbooks/backup-and-restore.md:21 | **Install the tools.** age, plus az, gcloud, kubectl and jq, and psql and pg_restore 16 or newer. | Merged | First-time setup, same file |
| runbooks/backup-and-restore.md:22 | **Create the key pair,** on your own machine: | Merged | First-time setup, same file |
| runbooks/backup-and-restore.md:24 | age-keygen -o li-backup.key | Merged | First-time setup, same file |
| runbooks/backup-and-restore.md:26 | It prints the public key (age1...). | Merged | First-time setup, same file |
| runbooks/backup-and-restore.md:26 | Keep the private key where it survives losing this machine: a password manager, or age -p -o li-backup.key.... | Merged | First-time setup, same file |
| runbooks/backup-and-restore.md:26 | Share it with a teammate, then delete the plain file. | Merged | First-time setup, same file |
| runbooks/backup-and-restore.md:26 | **Without it, no backup can be read.** Never commit it, even encrypted: this repository is public. | Merged | First-time setup, same file |
| runbooks/backup-and-restore.md:29 | terraform -chdir=infra/terraform/bootstrap init -backend-config="bucket=&lt;project>-tfstate" | Merged | First-time setup, same file |
| runbooks/backup-and-restore.md:30 | terraform -chdir=infra/terraform/bootstrap apply | Merged | First-time setup, same file |
| runbooks/backup-and-restore.md:31 | terraform -chdir=infra/terraform/bootstrap output backup_container_url | Merged | First-time setup, same file |
| runbooks/backup-and-restore.md:40 | **Release the Terraform changes.** This creates the backup service account, the empty backup-sas secret and... | Merged | First-time setup, same file |
| runbooks/backup-and-restore.md:41 | **Create the SAS:** make cloud-backup-sas. | Merged | First-time setup, same file |
| runbooks/backup-and-restore.md:42 | The release refuses to run while any REPLACE_ME remains. | Merged | First-time setup, same file |
| runbooks/backup-and-restore.md:46 | backup in terraform output workload_service_accounts (in envs/prod) | Merged | First-time setup, same file |
| runbooks/backup-and-restore.md:48 | The public key from step 2 | Merged | First-time setup, same file |
| runbooks/backup-and-restore.md:50 | **Test it:** run make cloud-backup, then the restore test below, then check the SAS and the alert. | Merged | First-time setup, same file |
| runbooks/bootstrap.md:46 | Nothing else, including jobs on branch pushes outside the prod environment, can get credentials. | Corrected | bootstrap.md |
| runbooks/bootstrap.md:79 | Terraform can't create OAuth clients for external users, so do this in the console under **APIs & Services**: | Corrected | bootstrap.md |
| runbooks/bootstrap.md:83 | openid, email, profile, and https://www.googleapis.com/auth/youtube.force-ssl. | Corrected | bootstrap.md |
| runbooks/bootstrap.md:87 | **Credentials → Create OAuth client ID → Web application**: | Corrected | bootstrap.md |
| runbooks/bootstrap.md:107 | Docker images; keeps the last 10 versions; nodes pull, github-deploy pushes | Corrected | bootstrap.md |
| runbooks/bootstrap.md:118 | To rotate the li_admin password, increment the default of db_admin_password_version in variables.tf, commit... | Corrected | bootstrap.md |
| runbooks/bootstrap.md:118 | Cloud SQL and Secret Manager get the new value together; re-run the services deploy afterwards so the migra... | Corrected | bootstrap.md |
| runbooks/bootstrap.md:133 | HTTPS load balancer forwarding rule (created in step 4) | Corrected | bootstrap.md |
| runbooks/bootstrap.md:174 | **It releases the IP, which changes the API hostname.** After re-creating, update values.env and push to ma... | Corrected | bootstrap.md |
| runbooks/bootstrap.md:194 | Fill deploy/k8s/overlays/prod/values/values.env from terraform output (each line names its output; | Corrected | bootstrap.md |
| runbooks/bootstrap.md:194 | CORS_ORIGINS is frontend_url), plus GOOGLE_CLIENT_ID. | Corrected | bootstrap.md |
| runbooks/bootstrap.md:194 | The release refuses to run while it still has placeholders. | Corrected | bootstrap.md |
| runbooks/bootstrap.md:195 | Add the frontend_url output as an authorized JavaScript origin on the OAuth client (step 5). | Corrected | bootstrap.md |
| todo.md:11 | Do both in the next release after it, once it's clear no rollback is needed. | Corrected | todo.md: marked ready to do |
| todo.md:15 | The code no longer uses the column, but the previous release still selects it, so it stays for one release. | Corrected | todo.md: marked ready to do |
| todo.md:15 | In the release after, once it's clear no rollback is needed: | Corrected | todo.md: marked ready to do |
| todo.md:19 | Write an onboarding guide for new developers | Done | written as onboarding.md |
| todo.md:21 | **Today:** what a new teammate needs is spread across the README, local-development.md, the runbook, releas... | Done | written as onboarding.md |
| todo.md:21 | The docs were also reorganized recently (docs/milestones/), so older links and habits point at old places. | Done | written as onboarding.md |
| todo.md:23 | **Goal:** one docs/onboarding.md that gets a new developer from zero to a merged change, linking to the exi... | Done | written as onboarding.md |
| todo.md:24 | **What the project is, and a tour of the repository:** what lives in services/, frontend/, infra/terraform/... | Done | written as onboarding.md |
| todo.md:25 | **Access to request,** and from whom: | Done | written as onboarding.md |
| todo.md:26 | GitHub collaborator (and prod reviewer, if they'll approve releases) | Done | written as onboarding.md |
| todo.md:28 | GCP IAM roles, only if they'll use make cloud-* or the console | Done | written as onboarding.md |
| todo.md:29 | Azure access, if needed | Done | written as onboarding.md |
| todo.md:30 | **Local setup:** make doctor, then local-development.md (dev sign-in, make dev-up, the frontend, tests). | Done | written as onboarding.md |
| todo.md:30 | Optionally the cloud tools. | Done | written as onboarding.md |
| todo.md:32 | branch from development; open a pull request or merge into main | Done | written as onboarding.md |
| todo.md:33 | every push to main is a release that someone approves (release-process.md) | Done | written as onboarding.md |
| todo.md:34 | commit message style | Done | written as onboarding.md |
| todo.md:36 | expand-then-contract migrations, and never editing a released one | Done | written as onboarding.md |
| todo.md:37 | unique test file names | Done | written as onboarding.md |
| todo.md:39 | Kubernetes values in values.env | Done | written as onboarding.md |
| todo.md:40 | checking make k8s-check before touching manifests | Done | written as onboarding.md |
| todo.md:41 | **Cost etiquette:** pause the environment after testing (make cloud-pause), and check with make cloud-status. | Done | written as onboarding.md |
| todo.md:42 | **Where to look when something breaks:** dashboard links, CI logs, the failed-run notes in first-deployment... | Done | written as onboarding.md |
| todo.md:43 | **A first task** that touches the whole flow: for example a small API or frontend change, taken through CI ... | Done | written as onboarding.md |
| todo.md:44 | **Link it** from the top of the README. | Done | written as onboarding.md |
| todo.md:46 | Have someone who hasn't worked on the project follow it, and fix what trips them up. | Moved | todo.md: Test the onboarding guide |
| todo.md:61 | Report on the Milestone 2 deliverables | Moved | first-deployment.md: Milestone 2 report checklist |
| todo.md:63 | Prepare the Prototype Review report (week 10, 10% of the grade) in docs/milestones/m2_prototype_review/. | Moved | first-deployment.md: Milestone 2 report checklist |
| todo.md:63 | Show how we implemented each deliverable from the course requirements: | Moved | first-deployment.md: Milestone 2 report checklist |
| todo.md:81 | **Today:** only the project owner can use the Google Cloud and Azure accounts, and in the app, only the own... | Corrected | todo.md |
| todo.md:88 | Also add each one as a **test user** on the OAuth consent screen (**APIs & Services → OAuth consent screen ... | Corrected | todo.md |
| todo.md:89 | **Azure** (subscription with rg-li-prod): invite each teammate as a guest (**Microsoft Entra ID → Users → I... | Corrected | todo.md |
| todo.md:90 | **App admins**, after the ADR 0002 release, one per teammate: | Corrected | todo.md |
| services/README.md:108 | Events the monitoring dashboard builds on: | Corrected | services/README.md |

</details>
