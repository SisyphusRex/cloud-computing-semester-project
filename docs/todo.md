# To do

Open work that isn't scheduled in the [implementation plan](milestones/m2_prototype_review/implementation-plan.md) yet. Move an item there, or delete it, once it's picked up.

## Finish the user-roles change (contract step)

[ADR 0002](architecture_decision_records/0002-invite-only-users-and-admin-roles.md) moved roles into the database. The release that shipped it kept two things for one release, so that the previous version still works during a rollback:
- **The empty `PROFESSOR_EMAILS` key** in `deploy/k8s/overlays/prod/values/values.env`. The previous pods read it from `li-config`, and `kubectl rollout undo` would fail if it were missing. Delete it.
- **Search's `INSERT` on `users`** (`0002_app_roles.sql`). Sign-in now only claims invitations (an `UPDATE`), so a new migration can `REVOKE INSERT ON users FROM li_search_role`.

Do both in the next release after it, once it's clear no rollback is needed.

## Write an onboarding guide for new developers

**Today:** what a new teammate needs is spread across the README, [local-development.md](local-development.md), the [runbook](runbooks/bootstrap.md), [release-process.md](release-process.md) and the [implementation plan](milestones/m2_prototype_review/implementation-plan.md), with no starting point or reading order. The docs were also reorganized recently (`docs/milestones/`), so older links and habits point at old places.

**Goal:** one `docs/onboarding.md` that gets a new developer from zero to a merged change, linking to the existing docs rather than repeating them:
- **What the project is, and a tour of the repository:** what lives in `services/`, `frontend/`, `infra/terraform/`, `deploy/k8s/`, `.github/workflows/`, `scripts/` and `docs/`, and which document to read for what.
- **Access to request,** and from whom:
  - GitHub collaborator (and `prod` reviewer, if they'll approve releases)
  - a test user on the OAuth consent screen
  - GCP IAM roles, only if they'll use `make cloud-*` or the console
  - Azure access, if needed
- **Local setup:** `make doctor`, then [local-development.md](local-development.md) (dev sign-in, `make dev-up`, the frontend, tests). Optionally the cloud tools.
- **How we work:**
  - branch from `development`; open a pull request or merge into `main`
  - every push to `main` is a release that someone approves ([release-process.md](release-process.md))
  - commit message style
- **Conventions that bite:**
  - expand-then-contract migrations, and never editing a released one
  - unique test file names
  - `li_common.logs`, not `logging`
  - Kubernetes values in `values.env`
  - checking `make k8s-check` before touching manifests
- **Cost etiquette:** pause the environment after testing (`make cloud-pause`), and check with `make cloud-status`.
- **Where to look when something breaks:** [dashboard links](monitoring/dashboard-links.md), CI logs, the failed-run notes in [first-deployment.md](milestones/m2_prototype_review/first-deployment.md).
- **A first task** that touches the whole flow: for example a small API or frontend change, taken through CI and one release.
- **Link it** from the top of the README.

Have someone who hasn't worked on the project follow it, and fix what trips them up.

## Tell users when the environment is paused

**Today:** while the environment is paused (`make cloud-pause`), the Cloud Run frontend still loads and Google sign-in still works, because neither depends on our infrastructure. Every API call then fails, and the app shows the generic "Could not reach the server." ([`client.ts`](../frontend/src/api/client.ts), `network_error`). To a teammate or grader that looks like a bug.

Two improvements, independent of each other:

1. **A clearer message for an unreachable API (small).** When the API can't be reached at all (`network_error`), show something like *"The service is paused to save cost. Ask the team to resume it."* instead of the generic error, at least on the first request after sign-in. Keep the generic wording for other failures. Add a vitest case.
2. **A maintenance banner while paused (more moving parts).** Show a banner on every page while the environment is paused, before anyone signs in.
   - `make cloud-pause` sets a flag the frontend can read, and `make cloud-resume` clears it as its last step, next to the namespace annotation.
   - The flag could be a Cloud Run environment variable read at container start (`gcloud run services update li-frontend --update-env-vars LI_PAUSED=1`, served by nginx as a small `/status.json`), or a static file in a public bucket.
   - Keep other tools from clearing the flag: releases and `rollback.yml` already skip while paused, but Terraform would remove an environment variable set by `gcloud`. Add `template[0].containers[0].env` to `ignore_changes` in [`modules/cloud-run-frontend`](../infra/terraform/modules/cloud-run-frontend/main.tf), or use the bucket file instead.
   - Update `cloud-power.sh`'s step list and the runbook.

## Report on the Milestone 2 deliverables

Prepare the Prototype Review report (week 10, 10% of the grade) in [`docs/milestones/m2_prototype_review/`](milestones/m2_prototype_review/). Show how we implemented each deliverable from the [course requirements](milestones/m1_project_proposal/project-requirements.md):

| Deliverable | What to show | Where the evidence is |
|---|---|---|
| **1. Initial deployment** | The live system: Cloud Run frontend, GKE Ingest and Search APIs behind the load balancer, Cloud SQL, Secret Manager, Artifact Registry; Azure for the CI identities (backups come in step 5). All provisioned with Terraform | [first-deployment.md](milestones/m2_prototype_review/first-deployment.md), [runbooks/bootstrap.md](runbooks/bootstrap.md), `infra/terraform/`, [dashboard links](monitoring/dashboard-links.md); release [`prod-2026-10-18.1`](https://github.com/SisyphusRex/cloud-computing-semester-project/releases/tag/prod-2026-10-18.1) |
| **2. CI/CD pipeline** | CI on every push (lint, tests against Postgres, compose smoke test, Terraform and Kubernetes checks, frontend and image tests); the release workflow (review sheet, read-only plan, one approval, ordered release, automatic rollback, tags); keyless OIDC to both clouds | `.github/workflows/`, [release-process.md](release-process.md), Actions run history |
| **3. Basic functionality** | Google sign-in, professor and student roles, registering a lecture through the YouTube API, search with timestamped deep links, working in production | Results in [first-deployment.md](milestones/m2_prototype_review/first-deployment.md), [real-youtube-test.md](milestones/m2_prototype_review/real-youtube-test.md); screenshots to take |

Also worth including:
- **The architecture as deployed,** and how it differs from the proposal: the frontend moved from Azure Static Web Apps to Cloud Run ([ADR 0001](architecture_decision_records/0001-frontend-on-cloud-run.md)).
- **What went wrong and how we fixed it:** the Azure region policy, GitHub's immutable OIDC subjects, the ConfigMap namespace, and Cloud Run's reserved `/healthz` (the table in first-deployment.md).
- **Cost so far and cost controls** (`make cloud-pause`), from the billing report.
- **AI usage:** the session logs in [`ai_usage/`](ai_usage/).

Before writing it, check the course page for a required format or length, and take screenshots while the environment is running (resume it with `make cloud-resume`).

## Give teammates access to the clouds and the app

**Today:** only the project owner can use the Google Cloud and Azure accounts, and in the app, only the owner will be a superuser once [ADR 0002](architecture_decision_records/0002-invite-only-users-and-admin-roles.md) is released. Teammates can't pause or resume the environment, read logs, check costs, or manage users.

Keep the teammates' email addresses **out of this repository** (it's public; see ADR 0002). Use the team's own contact list, and grant access by hand in each console.

1. **Google Cloud** (project `lecture-indexer-511419`): **IAM & Admin → IAM → Grant access**, for each teammate's Google account.
   - **Owner** if they're full co-owners of the project. That includes IAM and billing visibility.
   - Otherwise, enough for `make cloud-*`, the logs and the [database access guide](security/database-access.md): **Editor**, plus **Secret Manager Secret Accessor** on the `db-admin-password` secret only. Editor alone can't read secret values. Check that `make cloud-pause` / `cloud-resume` work for them; they change Cloud SQL and the cluster.
   - Also add each one as a **test user** on the OAuth consent screen (**APIs & Services → OAuth consent screen → Audience**). While the app is in testing mode, Google refuses sign-in for anyone else.
2. **Azure** (subscription with `rg-li-prod`): invite each teammate as a guest (**Microsoft Entra ID → Users → Invite external user**). Then assign a role on the subscription or on `rg-li-prod` (**Access control (IAM) → Add role assignment**): **Contributor** to manage resources, or **Reader** to look only. Azure for Students may restrict guest invitations; if it does, note what works here.
3. **App superusers**, after the ADR 0002 release, one per teammate:
   ```sh
   make cloud-create-superuser EMAIL=<their Google email>
   ```
   They then sign in with that Google account. Add `make cloud-admin ARGS="add-user <email> --role professor"` for anyone who also needs to create courses: superuser doesn't include professor.
4. **GitHub:** collaborator access, and `prod` environment reviewer for anyone who will approve releases ([release-process.md](release-process.md)).

Afterwards, have each teammate confirm with `make cloud-status` and a sign-in to the app. Record who has which access somewhere outside the repo, so it can be revoked at the end of the semester.

## Revoke superusers with `li-admin`

**Today:** `li-admin create-superuser` is the only way to grant superuser, and the app deliberately can't change superusers ([ADR 0002](architecture_decision_records/0002-invite-only-users-and-admin-roles.md)). Nothing removes the flag except a hand-written SQL `UPDATE` as `li_admin` ([database access guide](security/database-access.md)). That writes no `user_audit` row, so the change leaves no record.

**Goal:** `li-admin revoke-superuser EMAIL [--keep-admin]` in [`admin.py`](../services/common/src/li_common/admin.py):
- It clears `is_superuser`, and also `is_admin` unless `--keep-admin` is given. The database check (superuser implies admin) allows either.
- It goes through `users.update(..., actor_id=None)`, so the change is audited like the other CLI commands.
- It refuses to remove the **last** superuser, since nobody could grant admin after that. `--force` overrides this.
- It's safe to re-run, and errors clearly on an unknown email.
- In prod: `make cloud-admin ARGS="revoke-superuser EMAIL"`. `scripts/cloud-admin.sh` passes the arguments through, so no new script is needed.
- Tests in `services/common/tests/test_admin_cli.py`: revoke, `--keep-admin`, the last-superuser guard, and the audit row.
- Docs: the `li-admin` list in `services/README.md`, and the database access guide, which should point to this command instead of SQL.
- Optionally, also `remove-admin` and `disable`, so the CLI can undo everything it can grant.

## Optional

Ideas worth considering. Nothing depends on them; pick one up only if it's worth the time.

### Keep the sign-in across page refreshes

**Today:** the session (the Google ID token, or the dev token) lives only in React state ([`AuthContext.tsx`](../frontend/src/auth/AuthContext.tsx)). Refreshing the page signs you out. In production that means another Google sign-in after every reload; when testing locally, it means typing the account again. This was deliberate: a token in browser storage can be read by any script that gets onto the page.

**Option:** keep the session in `sessionStorage`, restore it on load, and clear it on sign-out and when the token expires (the existing timer). `sessionStorage` is limited to one tab and cleared when the tab closes, unlike `localStorage`.

- **Risk:** an injected script could read the ID token and use it against the APIs until it expires (about an hour). The nginx Content-Security-Policy (`script-src 'self'` plus Google's sign-in script, in [`security-headers.conf`](../frontend/nginx/security-headers.conf)) makes that unlikely, but it's still more exposure than memory.
- **Don't persist the YouTube access token.** It can manage the professor's channel; keep it in memory as now.
- If done, add a vitest case (restored on load, cleared on sign-out and on expiry), and note the trade-off in the M3 security review.
