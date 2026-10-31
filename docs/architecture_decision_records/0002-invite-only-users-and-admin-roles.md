# ADR 0002: Invite-only sign-in, with roles set by admins in the database

- **Status:** Accepted; the superuser tier is superseded by [ADR 0003](0003-merge-superuser-into-admin.md)
- **Date:** 2026-10-19
- **Changes:** how users get the professor role in the Milestone 2 implementation (the `PROFESSOR_EMAILS` allowlist)

## Context

In Milestone 2, `load_user` in `services/common/src/li_common/auth.py` created a `users` row at every new Google sign-in. Anyone whose email was in `PROFESSOR_EMAILS` became a professor, and everyone else a student. The list lived in `deploy/k8s/overlays/prod/values/values.env`. That caused three problems:

- **The list was public.** `values.env` is committed to a public repository, so professors' email addresses were published, and they stay in the Git history.
- **Roles never went away.** The upsert never downgraded `professor`, so removing an email from the list didn't demote anyone. Demotion needed a manual database change.
- **Changing a role needed a release.** Adding a professor meant editing `values.env` and deploying.

Anyone with a Google account could also sign in and become a student. That's more open than a course tool needs.

The design is shaped by one constraint: users are keyed by the Google ID token's `sub`, and we only learn it when someone signs in for the first time. So an admin can't create a complete user row ahead of time. What an admin can create is an **invitation for an email address**.

## Decision

**Sign-in is invite-only, and roles live only in the `users` table.** The tiers follow Django's model:

| Who | Can | How they get it |
|---|---|---|
| **Superuser** | everything an admin can, plus grant and revoke admin | `li-admin create-superuser EMAIL`, a CLI run with database-admin credentials (`make cloud-create-superuser EMAIL=…` in prod; seeded automatically locally) |
| **Admin** | invite emails as student or professor, change a user's role, disable and re-enable accounts | a superuser turns on *Admin* on the Admin page |
| **Professor** | create courses, register lectures | invited (or promoted) by an admin |
| **Student** | browse and search courses | invited by an admin |

- `users.role` stays `student | professor`. **`is_admin` and `is_superuser` are separate flags** on top of the role, so a professor can also be an admin, the way Django's `is_staff`/`is_superuser` work alongside a user's other permissions.
- **An invitation is a `users` row with `google_sub IS NULL`.** The first sign-in with a verified Google email that matches it, ignoring case, claims the row and stores the `sub`. An email that wasn't invited gets 403 `not_invited`.
- **Changes take effect on the next request.** Each request already reads the user's row, so demoting or disabling someone works right away, without a release.
- **The superuser flag is CLI-only.** No API endpoint sets `is_superuser`, so taking over the top tier needs database-admin access, not just a stolen admin session.
- **Every change is audited.** Invites, role changes, admin grants and disables write a row to `user_audit` (actor, target, action, details, time) in the same transaction, and log a structured event.
- `PROFESSOR_EMAILS` is removed from the code, the Deployments, the compose files and the docs. Its `values.env` key stays, empty, for one release, so that `kubectl rollout undo` to the previous pods still finds it (see [todo](../todo.md)).

## Alternatives considered

| Option | Why not |
|---|---|
| Open sign-in (anyone becomes a student), where admins only pre-assign roles | Less admin work, but anyone with a Google account gets in; we want course access limited to people we invited |
| A single `admin` value in `role` | Simpler, but an admin couldn't also be a professor who owns courses, and there'd be no tier that's out of reach of the web UI |
| Four values in `role` (student, professor, admin, superuser) | Same problem: one column can't express "professor who is also an admin" |
| A bootstrap email in Secret Manager, made superuser at sign-in | No extra command, but it's config that keeps granting the top role for as long as it's set, which is what we're moving away from |
| A documented SQL procedure instead of an admin page | Fine as a stopgap, but every change would need database-admin access and leave no audit trail |

## Consequences

- **Admins must invite every user, students included.** The Admin page takes a pasted list of emails, so a whole class can be invited at once.
- **The first superuser is a deliberate step** after the release that adds this (`make cloud-create-superuser`, documented in the [bootstrap runbook](../runbooks/bootstrap.md)). Users who existed before the migration keep their rows and roles.
- **Email changes at Google can strand an account.** If someone's Google account changes but their email doesn't, or the reverse, an admin may need to delete the unclaimed invitation and invite the new address. Invitations that were never claimed can be deleted. Accounts that have signed in are disabled instead, because their courses reference them.
- **The old allowlist stays in the Git history.** Removing it from `values.env` doesn't unpublish the email address.
- **For the M3 security review:**
  - who can grant which tier
  - that superuser needs database-admin access
  - the `user_audit` trail
  - that the Ingest API, not Search, holds the admin endpoints (Search keeps its read-mostly database role)
