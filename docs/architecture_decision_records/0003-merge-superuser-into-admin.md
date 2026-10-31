# ADR 0003: Merge superuser into admin, and let admins switch role

- **Status:** Accepted
- **Date:** 2026-10-31
- **Changes:** the admin and superuser tiers in [ADR 0002](0002-invite-only-users-and-admin-roles.md). Invite-only sign-in, the `users.role` column and the audit trail stay as they are.

## Context

ADR 0002 put two flags on top of `users.role`: `is_admin` and `is_superuser`. In practice:

- **The second tier added friction, not safety we used.** No route required a superuser; the difference was a few inline checks when changing admins. Making a superuser needed a CLI run with database-admin credentials.
- **Admins couldn't switch role.** The role check is an exact match, so an admin with the `student` role gets 403 on every professor route. Nobody could change their own account, so switching meant running `make cloud-admin`.

## Decision

**There is one admin tier, `is_admin`, with the powers the superuser had, and any admin can change their own role.**

| Action | Admin |
|---|---|
| Invite; change anyone's role, including their own | yes |
| Grant or revoke admin; disable or re-enable others, including other admins | yes |
| Delete any unclaimed invitation | yes |
| Disable themselves, or change their own admin flag | no (403) |

- **`role` stays a separate column,** so a professor can still be an admin. Admin doesn't include professor; an admin who needs the professor routes switches role.
- **A switch changes the stored role.** It isn't a temporary view: it goes through the existing `PATCH /ingest/admin/users/{id}`, lasts across sign-ins, and is audited with the same user as actor and target. Courses the admin owns stay theirs. A student-role admin can't manage them until they switch back.
- **The self-block protects the last admin.** The admin making a change always remains an admin, so the API can't remove the last one and no separate guard is needed. If two admins demote each other at the same moment, `li-admin create-admin` recovers access.
- **`li-admin create-admin` replaces `create-superuser`.** It's still how the first admin is made, since nobody can sign in before that.

### Rollout

`users.is_superuser` is removed over two releases, because a rollback redeploys old code against the same database ([migration rule](../release-process.md)):

1. **This release:** the code stops using the column, and `0005_merge_superuser_into_admin.sql` drops the `users_superuser_is_admin` check. Without that, revoking admin from a former superuser would fail. After a rollback, a revoked user stays locked out, because the old code also requires `is_admin`.
2. **Next release:** a new migration drops the column (see [todo](../todo.md)).

No data changes: the old check guarantees that every superuser already has `is_admin`.

## Alternatives considered

| Option | Why not |
|---|---|
| Keep admin grants CLI-only | Keeps the top tier out of the web UI, but every admin change needs database-admin credentials, which is the friction we're removing |
| Let admins grant admin but not revoke it | Stops one admin locking out the others, but cleaning up a compromised admin would need the CLI |
| A temporary view-as toggle | Their real role would stay unchanged, but it needs a new request header, handling in both services and its own audit rule, for no extra capability |
| Let the admin flag bypass role checks | Removes the need to switch, but admins could no longer see the app as a student, and role checks would stop meaning what they say |

## Consequences

- **A stolen admin session now reaches the top tier.** ADR 0002 kept one tier out of the web UI's reach; this gives that up. An attacker with an admin's token, which lasts about an hour, could grant admin or disable other admins, but not disable or demote the account they're using. `user_audit` records it, and `li-admin` can restore access. A note for the M3 security review.
- **Every existing admin gains the former superuser powers** on release. Check who they are first with `make cloud-admin ARGS=list`.
- **`make cloud-create-superuser` is gone.** Use `make cloud-create-admin`.
- **A local role switch doesn't survive `make dev-up`,** because the compose `seed` service sets the default accounts' roles again.
