# Release process

How code gets from `main` to production, what to check before approving a release, and how to undo one. The workflows are [release.yml](../.github/workflows/release.yml) and [rollback.yml](../.github/workflows/rollback.yml).

## The flow

Every push to `main` (a fast-forward or a PR merge) starts one **Release** run:

```
push to main
  ├─ ci        waits for CI to pass on this commit
  ├─ review    review sheet: everything since the last prod-* tag    (no credentials)
  └─ plan      pause check + the real Terraform plan                  (read-only, prod-plan)
        │
        ▼  ONE approval in the prod environment
  release   1. terraform apply of exactly that plan     (only if it has changes)
            2. Cloud SQL backup                          (only if there are new migrations)
            3. build + push ingest, search, backup, frontend images, tagged with the commit SHA
            4. migrations (Job)
            5. roll out ingest + search                  → automatic undo if a rollout fails
            6. frontend to Cloud Run with no traffic, check it, then switch traffic
            7. check the API through the load balancer   → undo the services if it doesn't answer
        │
        ▼
  tag       prod-YYYY-MM-DD.N + a GitHub Release listing the commits
```

- **While paused** (`make cloud-pause`), the run stops after `plan` with a warning, and nobody is asked to approve. After `make cloud-resume`, start the release again: **Actions → Release → Run workflow** on `main` (or `gh workflow run release.yml --ref main`).
- **Pull requests** into `main` get an early Terraform plan as a comment (`terraform.yml`). That plan is only a preview. The plan that matters is the one in the release run, because that's the one that gets applied.
- **Before merging**, `make release-diff` prints the same review sheet locally. On the website, compare the last release with `development`: `https://github.com/SisyphusRex/cloud-computing-semester-project/compare/<last prod-* tag>...development` (the latest tag is at the top of **Releases**).

## Tags

Each successful release tags its commit `prod-YYYY-MM-DD.N` (for example `prod-2026-10-18.1`) and creates a GitHub Release.

- **Review base:** the next review sheet lists everything since the latest tag.
- **Rollback target:** every tagged commit has its images in Artifact Registry, so `rollback.yml` can return to it. A rollback to a tag from before backups leaves the backup CronJob as it is.
- **Record:** the Releases page shows what was in production and when, which helps with the milestone reports.

A tag ruleset protects `prod-*` tags from being moved or deleted. Milestone tags (`m2`, `m3`) can be added by hand on top.

## On the website (no `gh` needed)

Everything in a release can be done from github.com; `gh` only saves clicks. You need write access to the repository, and to be a `prod` reviewer to approve.

| Task | On github.com |
|---|---|
| **Start a release again** (after a pause, or to retry) | **Actions → Release → Run workflow**, branch `main`, **Run workflow** |
| **Roll back** | **Actions → Roll back → Run workflow**, branch `main`, type the tag (for example `prod-2026-10-18.1`), **Run workflow** |
| **Read the review sheet and plan** | Open the run, click the **Review sheet** job in the left sidebar and expand its **Review sheet** step (for the plan: the **Terraform plan (read-only)** job, **Plan** step). The same text appears as job summaries on the run page, but GitHub shows those only once the run has finished |
| **Approve or reject** | On the run page, **Review deployments**, tick `prod`, then **Approve and deploy** or **Reject** |
| **Cancel a run** | On the run page, **Cancel workflow** (top right) |
| **Find release tags** | **Releases** (right-hand side of the repository page) lists every `prod-*` tag with its commits |

**Run workflow** only offers workflows that have a manual trigger (`workflow_dispatch`): Release and Roll back. Always pick the `main` branch: the `prod` environment rejects any other.

## Before you approve

The approval is the only point where production credentials are handed out. After you click **Approve**, the workflow runs with Editor rights on GCP and Contributor on Azure, applies Terraform, and migrates the database, all without stopping. Self-approval is allowed, so often the reviewer is also the author. **Your review is the safeguard.**

Open the run and read the **Review sheet** job's log and the **Terraform plan** job's **Plan** step (walkthrough below):

| Area | How | Stop and ask if you see |
|---|---|---|
| **Workflows and `scripts/ci/`** (⚠) | Read every changed line | Anything new done with credentials: printing environment variables or tokens, `terraform destroy`, new third-party actions, new `curl` to unknown hosts. The workflow that runs is the version on `main` right now |
| **Terraform plan** | Read the plan job's output | `destroy`, or `-/+` (replace), on Cloud SQL `li-pg`, the `li-api` IP (the hostname would change), the cluster, or Cloud Run; new IAM roles; bigger tiers or always-on instances. On a release with no infra changes the plan says "no changes"; anything else means the cloud has drifted from the code |
| **Migrations** (⚠) | Read the SQL in the review sheet | `DROP`, renames, rewrites of existing data, `NOT NULL` without a default, anything the *previous* release can't run against (see the migration rule). A note about an edited old migration means the edit won't take effect |
| **`values.env`** | Read the diff | `CORS_ORIGINS` and `API_HOSTNAME` must match `terraform output` |
| **Commits** | The list since the last tag | Anything you didn't expect to ship |
| **Timing** | — | Someone is demoing or testing; nobody can watch the run for the next 15 minutes |

**Why it has to happen before approval:**
- **The apply can't be stopped.** Step 1 applies the exact plan you read, without pausing.
- **Migrations can't be undone** without restoring a backup and losing newer data.
- **A workflow change runs with production credentials** the moment you approve. Afterwards it's too late to read it.

If something looks wrong, **reject** the run. Nothing has happened yet; fix it on `development` and merge again.

### Reviewing as a teammate

How a `prod` reviewer who didn't write the change goes through a waiting release, on github.com only:

1. **Notice it.** GitHub emails the `prod` reviewers *"Deployment review requested"*, and the Actions tab shows the Release run as **Waiting**. Open the run.
2. **Who pushed what.** The top of the run page shows the commit, the branch (`main`) and who pushed it. Click the commit and read its message.
3. **Everything this release ships, not just the last commit.** Open **Releases**, note the latest `prod-*` tag, and open `https://github.com/SisyphusRex/cloud-computing-semester-project/compare/<that tag>...<commit>`. Or open the **Review sheet** job and expand its **Review sheet** step, which lists the same commits and files. The branch's **Activity** page (`…/activity?ref=main`) shows each push to `main` with a "compare changes" link.
4. **Read the risky parts, in this order.** On the compare page's **Files changed** tab, type a path into the filter above the file tree. Mark files as **Viewed** as you go.

   | Filter / place | Why | Reject if |
   |---|---|---|
   | `.github/workflows`, `scripts/ci` | Runs with production credentials as soon as you approve | Printing environment variables or tokens (`env`, `printenv`, `set -x`); `curl` to unknown hosts; `terraform destroy`; new `uses:` actions from unfamiliar publishers; wider `permissions:`; a changed `environment:` |
   | **Terraform plan** job → **Plan** step | Approving applies exactly this plan | Anything but "No changes" that the commits don't explain; any unexplained `destroy` or `-/+` on the database, the IP or the cluster |
   | `db/migrations` | Runs once, can't be undone | `DROP`, renames, data rewrites, an edited old migration |
   | `deploy/k8s/overlays/prod/values/values.env` | Which site may call the API, and which OAuth client signs users in | URLs that aren't ours; a changed `GOOGLE_CLIENT_ID` |
   | `services`, `frontend` | App behavior; CI already tested it | Changes no commit message explains |

5. **CI passed.** The run's **ci / CI passed on this commit** job must be green.
6. **Ask, don't guess.** Comment on the commit or message the author. If it stays unclear, **Review deployments → Reject** with a comment saying why. Nothing has been deployed, so rejecting costs nothing.
7. **Approve with a note.** **Review deployments**, tick `prod`, write what you checked (for example *"Workflows and migrations reviewed, plan has no changes, values.env OK"*), then **Approve and deploy**. The comment stays in the deployment history.

## Migration rule: expand first, contract later

A rollback (below) redeploys old code but keeps the database as it is. So every migration must keep the **previous** release working:
- **Add, then remove later:** new columns are nullable or have defaults, and new tables are fine. Drop a column only in a later release, after no code uses it.
- **Rename in steps:** add the new column, write to both, switch reads, then drop the old one, across several releases.
- **Never edit a migration that has been released.** Add a new one.

## When something goes wrong

**If a release fails its own checks, you don't need to undo anything.** The old API pods keep serving until the new ones pass `/readyz`, a failed rollout runs `kubectl rollout undo`, and the frontend gets traffic only after its check passes. Fix the bug and merge again. If the run stopped partway, read the failed step: the steps before it took effect (an apply, a backup, migrations) and the steps after it didn't. The next release continues from there.

**If the problem reached production:**

| What's wrong | What to do |
|---|---|
| **Bad code** (API or frontend) | Run the [rollback](#on-the-website-no-gh-needed) with the last good `prod-*` tag and approve it, or use `gh workflow run rollback.yml --ref main -f tag=<tag>`. Then **revert the bad commit on `development` and merge**, or the next release ships it again |
| **Bad data** (from a migration) | Restore the backup the release took (the [Azure backups](runbooks/backup-and-restore.md) are the fallback), then run the rollback as above. **Restoring overwrites the whole database; anything written since the backup is lost.** The backup ID is in the release summary. Use the Cloud Console (**SQL → li-pg → Backups**, pick "before release …", then **Restore** to `li-pg`) or `gcloud sql backups restore <id> --restore-instance li-pg` |
| **Bad infrastructure** (Terraform) | Revert the commit on `development` and merge; the next release plans the reverse change. Check that plan especially carefully. A deleted stateful resource (the database) can only come back from a backup |

The rollback redeploys that tag's images and config, with no migrations and no Terraform, then checks the API through the load balancer. It **fails** if the environment is paused (nothing was rolled back; run `make cloud-resume` and start it again), if the tag's images are gone, or if the API doesn't answer afterwards. Artifact Registry keeps the newest 10 versions of each image, plus anything under 30 days old, so recent tags are always available.

**Emergency, frontend only:** moving traffic back is faster than a rollback, because it doesn't wait for a run. In the Cloud Console, open **Cloud Run → li-frontend → Revisions → Manage traffic** and give the previous revision 100%, or use `gcloud run services update-traffic li-frontend --region us-central1 --to-revisions=<previous>=100`.
