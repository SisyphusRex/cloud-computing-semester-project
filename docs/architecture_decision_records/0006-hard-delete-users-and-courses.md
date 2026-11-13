# ADR 0006: Let admins delete accounts, and let owners and admins delete courses

- **Status:** Accepted
- **Date:** 2026-11-13
- **Changes:** the "accounts that have signed in are disabled instead" rule in [ADR 0002](0002-invite-only-users-and-admin-roles.md). Invite-only sign-in, roles and the audit trail stay as they are.

## Context

Before this change, the only things anyone could delete were lectures (Manage page) and invitations nobody had claimed (Admin page). An account that had signed in could only be disabled, and a course could not be removed at all. That was the database's doing, not a policy: `courses.owner_id`, `user_audit.actor_id` and `users.invited_by` all referenced `users` with no `ON DELETE` rule, so Postgres refused the delete.

So test accounts, people who left, and courses made by mistake stayed in the database, and in the course list everyone sees.

## Decision

- **Admins can delete any account but their own** with `DELETE /ingest/admin/users/{id}`, the endpoint that used to delete only invitations. The Admin page shows *Delete* next to *Disable* and asks for confirmation first. Admins can't delete themselves, the same way they can't disable themselves, so there is always an admin left.
- **Deleting a professor deletes their courses**, and with them the lectures and segments, which already cascade from `courses`. The confirmation says so.
- **A course can be deleted by its owner or by any admin** (`DELETE /ingest/courses/{id}`). Owners use the Manage page. Admins get a Courses table on the Admin page, built from `GET /search/courses`. Anyone else gets `404`, as if the course didn't exist.
- Migration `0007_user_delete.sql` rebuilds the three foreign keys: `courses.owner_id` gets `ON DELETE CASCADE`, and `user_audit.actor_id` and `users.invited_by` get `ON DELETE SET NULL`.
- **The audit trail survives.** The delete writes its own `user_audit` row (`delete_user`, or `delete_invitation` for an invitation) with the email, role and number of courses deleted, before the user row goes. Course deletes are logged (`course_deleted`), not audited, because `user_audit` tracks users.

## Alternatives considered

| Option | Why not |
|---|---|
| Keep disable-only | Disabled accounts and their courses stay visible to every student, and there is no way to clean up test data from the UI |
| Refuse (`409`) to delete a professor who still owns courses | Safer, but the admin then has to delete each course first. The confirmation dialog states the cascade instead |
| Soft delete (a `deleted_at` column) | Every query would need to filter on it, and nothing needs the data back. The nightly backups ([ADR 0004](0004-database-backups-to-azure.md)) cover mistakes |
| Delete the courses in application code, without changing the foreign key | Works, but any other code path that deletes a user would hit the foreign key error again. The schema rule covers every path |

## Consequences

- **Deletes can't be undone from the app.** Restoring a deleted course or account means a restore from backup ([backup-and-restore runbook](../runbooks/backup-and-restore.md)).
- **`user_audit.actor_id IS NULL` now has two meanings:** the `li-admin` CLI, or an admin who was later deleted. The deleted admin's own `delete_user` row records their email, so who they were can still be traced.
- **A stolen admin session can now delete data**, not just disable accounts ([security review notes](../security/review-notes.md)). It still can't delete the account it's using, and every user delete is audited.
- The migration only adds `ON DELETE` rules, so the previous release runs against it unchanged ([release process](../release-process.md)).
