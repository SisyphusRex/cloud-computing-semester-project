# To do

Open work that isn't scheduled in the [implementation plan](milestones/m2_prototype_review/implementation-plan.md) yet. Move an item there, or delete it, once it's picked up.

## Move user roles into the database, set by admins

**Today:** the professor role comes from the `PROFESSOR_EMAILS` allowlist in `deploy/k8s/overlays/prod/values/values.env`. At each sign-in, [`load_user`](../services/common/src/li_common/auth.py) gives anyone on the list the professor role; everyone else is a student. Problems:
- **The list is public.** `values.env` is committed to a public repository, so the professors' email addresses are published, and they stay in the Git history.
- **Roles never go away.** Once an account has been a professor, it stays one even after it's removed from the list (the upsert keeps `professor`). Demoting someone needs a manual database change.
- **Changing roles needs a release.** Adding a professor means editing `values.env` and deploying.

**Goal:** roles live only in the `users` table, and an admin sets them.
- Add an `admin` role, and decide how the first admin is created (for example a one-time `li-migrate`-style command, or a single bootstrap email kept in a `prod` secret).
- Give admins a way to promote and demote users: an admin page in the frontend backed by an Ingest API endpoint, or a documented SQL procedure to begin with.
- Stop reading `PROFESSOR_EMAILS` in [`config.py`](../services/common/src/li_common/config.py) and `auth.py`. Remove it from `values.env`, `docker-compose.yml`, `docker-compose.google.yml`, `.env.example` and the docs. Keep a dev-only way to get a professor locally (dev sign-in's `prof@example.edu`).
- New sign-ins default to student. Demotion takes effect on the next request.
- Tests: role changes, demotion, non-admins can't change roles.
- Update the M3 security review (who can grant roles, and the audit trail).

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
