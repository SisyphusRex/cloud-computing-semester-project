# Onboarding

From zero to a merged change on Lecture Indexer (LI). This page gives the order and links to the details; the [documentation map](README.md) lists everything else.

## What the project is

A professor registers a YouTube lecture, LI indexes its auto-generated captions, and a student searches a course and jumps to the moment a term is spoken. It's a two-cloud course project: nearly everything runs on Google Cloud, and encrypted database backups go to Azure. Read the [root README](../README.md), then [architecture.md](architecture.md).

| Path | What's there | Read |
|---|---|---|
| `services/` | The Ingest and Search APIs (Flask), and the shared `li_common` package | [services/README.md](../services/README.md) |
| `frontend/` | React app, served by nginx on Cloud Run | [Architecture: Frontend](architecture.md#frontend) |
| `db/migrations/` | Numbered SQL migrations | [Migration rule](release-process.md#migration-rule-expand-first-contract-later) |
| `infra/terraform/` | Both clouds' infrastructure | [Bootstrap runbook](runbooks/bootstrap.md) |
| `deploy/k8s/` | Kustomize manifests | [Architecture: Kubernetes](architecture.md#kubernetes-layout) |
| `backup/` | The backup CronJob's image | [Backup runbook](runbooks/backup-and-restore.md) |
| `.github/workflows/` | CI, release and rollback | [Release process](release-process.md) |
| `scripts/` | Dev, CI, backup and cost-control helpers | `make help` lists the entry points |
| `docs/` | Everything written down | [Documentation map](README.md) |

## Access to request

Ask the project owner. Nothing here is needed to run the app locally. Details are in the [team access runbook](runbooks/team-access.md).

- **GitHub:** collaborator access, and `prod` reviewer if you'll approve releases.
- **Google:** a test user on the OAuth consent screen, needed for real sign-in. While the app is in testing mode, Google refuses everyone else.
- **The app:** an invitation. Sign-in is invite-only, so an admin adds your Google account on the Admin page.
- **GCP IAM roles:** only if you'll use `make cloud-*` or the console.
- **Azure:** only if you'll work on backups.

## Local setup

```sh
make doctor
```

Then follow [local-development.md](local-development.md): dev sign-in, `make dev-up`, the frontend, and the tests. The cloud tools are optional.

## How we work

- **Branch from `development`.** Branches are named for the person and topic, like `twp__update_docs`.
- **Open a pull request into `development`.** CI runs on it. Use `make test-db`, not `make test`, locally: plain `make test` skips every database test and still passes.
- **Merging `development` into `main` is a release.** Every push to `main` starts a Release run that someone approves, even for a docs-only change ([release process](release-process.md)).
- **Commit messages** are one imperative sentence with a capital letter and no prefix: *Add the resource tags Claude Code session log*. Add a body when the reason isn't obvious.
- **AI usage is logged.** Claude Code sessions are recorded in [ai_usage/](ai_usage/), one file per session, by milestone.

## Conventions that bite

- **Migrations are expand-then-contract,** and a released migration is never edited ([why](release-process.md#migration-rule-expand-first-contract-later)).
- **Test file names are unique** across the workspace, because of pytest's default import mode.
- **The logging module is `li_common.logs`,** not `logging`, which would shadow the standard library.
- **Kubernetes values go in `values.env`:** `deploy/k8s/overlays/prod/values/values.env`.
- **Run `make k8s-check` after touching manifests,** if you have `kustomize` and `kubeconform`. CI runs it anyway.
- **Run `make docs-check` after moving a document.**
- **The repository is public.** No personal email addresses, secrets or keys, even encrypted.

## Cost etiquette

Everything running costs real credits. After testing, pause the environment, and check that it stopped:

```sh
make cloud-pause
make cloud-status
```

## When something breaks

- **Locally:** [troubleshooting](local-development.md#troubleshooting).
- **In CI:** the failed job's log in the [Actions tab](https://github.com/SisyphusRex/cloud-computing-semester-project/actions).
- **In a release:** [When something goes wrong](release-process.md#when-something-goes-wrong), and past failures in [first-deployment.md](milestones/m2_prototype_review/first-deployment.md#results-2026-10-18) and [azure-backup-setup.md](milestones/m3_technical_review/azure-backup-setup.md#problems-we-hit).
- **In production:** the [Grafana dashboard](monitoring/dashboard-links.md#grafana-cloud) first, then logs and consoles in [Environment and dashboard links](monitoring/dashboard-links.md).
- **A backup alert:** [When the alert fires](runbooks/backup-and-restore.md#when-the-alert-fires).

## A first task

Take a small change through the whole flow. For example, the clearer message for an unreachable API in the [wishlist](wishlist.md#tell-users-when-the-environment-is-paused) touches the frontend and needs a vitest case. Branch, open a pull request into `development`, get CI green, and watch it go out in the next release.

This guide hasn't been tested by someone new yet. If something trips you up, fix it here.
