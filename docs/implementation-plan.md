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
| 5 | Backup CronJob + Azure storage, monitoring module, security review doc | partly done: backups and their failure alert ([ADR 0004](architecture_decision_records/0004-database-backups-to-azure.md)), released 2026-10-31 in `prod-2026-10-31.3`, with the restore test passed ([record](milestones/m3_technical_review/azure-backup-setup.md)); the rest of monitoring and the security review doc are still to do |

| Milestone | Due | Needs |
|---|---|---|
| M2 Prototype Review | Week 10 | Initial deployment, CI/CD pipeline, basic functionality (steps 3–4) |
| M3 Technical Review | Week 12 | Monitoring, security review, documentation (step 5) |
| Final Demonstration | Week 14 | Live demo, architecture talk, cost analysis, AI-usage reflection, lessons learned |

## Remaining: step 5

- `modules/monitoring`: dashboard, log-based metrics, and the remaining alert policies (the backup alert is done).
- The security review in `docs/milestones/m3_technical_review/`, including the YouTube scope correction. Its inputs are collected in [security/review-notes.md](security/review-notes.md).

Smaller open work is in the [to-do list](todo.md).

## Verification target

- `make lint`, `make test-db`, `make dev-up`, `make smoke`; `make frontend-test`; `make k8s-check`.
- `terraform -chdir=infra/terraform/envs/prod test` (no credentials), then `plan` against the real project; `make k8s-check`.
- CI green on a PR touching each top-level directory.
- End to end: sign in on the Cloud Run URL, register a captioned video, search a spoken term, and the link opens at the right second.
