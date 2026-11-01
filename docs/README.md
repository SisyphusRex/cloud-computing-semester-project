# Documentation

Where to find things, and where new things belong. New to the project? Start with [onboarding](onboarding.md).

## What to read

| You want to… | Read |
|---|---|
| Understand what LI is and run it | [Root README](../README.md), then [local development](local-development.md) |
| Join the project | [Onboarding](onboarding.md) |
| Understand the design and why it's that way | [Architecture](architecture.md), then the [ADRs](architecture_decision_records/) |
| Learn how search works | [Transcript search](search/transcript-search.md) |
| Call the APIs or configure the services | [Services](../services/README.md) |
| See where the project stands | [Implementation plan](implementation-plan.md) and [to-do list](todo.md) |
| Ship or undo a change | [Release process](release-process.md) |
| Provision, pause or tear down the cloud environment | [Bootstrap runbook](runbooks/bootstrap.md) |
| Back up or restore the database | [Backup runbook](runbooks/backup-and-restore.md) |
| Test against real Google and YouTube | [Real Google test](runbooks/real-google-test.md) |
| Find a console, a resource or an environment value | [Environment and dashboard links](monitoring/dashboard-links.md) |
| Look at, change or rotate the monitoring dashboard | [Monitoring runbook](runbooks/monitoring.md) |
| Query the production database | [Database access](security/database-access.md) |
| Prepare the security review | [Security review notes](security/review-notes.md) |
| See what was submitted or what happened on a date | [Milestones](milestones/) and [AI usage logs](ai_usage/) |

## Where a new fact belongs

Each kind of fact has one home. Other pages link to it instead of repeating it.

| Kind of fact | Home |
|---|---|
| A design choice and its reason | The Decisions table in [architecture.md](architecture.md); a new [ADR](architecture_decision_records/) if it replaces a past decision or had real alternatives |
| A procedure someone will repeat | A [runbook](runbooks/) |
| A value from our environment | [Environment and dashboard links](monitoring/dashboard-links.md) |
| Open work | [todo.md](todo.md), or [implementation-plan.md](implementation-plan.md) if it's a planned step |
| A note for the security review | [security/review-notes.md](security/review-notes.md) |
| What happened on a date | A record in that milestone's folder |

**Records stay as written.** Milestone write-ups and AI usage logs describe a date, so don't update them when the system changes. Each milestone write-up has a banner pointing to the current procedure. ADRs keep their text too: add a dated **Update** line or a new ADR when one stops being true.

`make docs-check` runs in CI and fails on a broken link, heading anchor or repository path. Run it after moving a file.
