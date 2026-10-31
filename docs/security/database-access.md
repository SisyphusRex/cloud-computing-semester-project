# Accessing the production database

How to run a query against the production Postgres database (Cloud SQL instance `li-pg`), for one-off checks such as the duplicate-email check before [ADR 0002](../architecture_decision_records/0002-invite-only-users-and-admin-roles.md)'s migration.

For **user accounts**, don't use SQL: use the Admin page, or `make cloud-admin ARGS=list` / `make cloud-create-admin EMAIL=...` ([runbook](../runbooks/bootstrap.md), "First deploy"). Those write the audit trail; hand-written SQL doesn't.

## Why there's no direct connection

The instance has **only a private IP** (`ipv4_enabled = false` in [`infra/terraform/modules/cloudsql`](../../infra/terraform/modules/cloudsql/main.tf)), so it can't be reached from a laptop. Inside GKE, the services connect through the Cloud SQL Auth Proxy sidecar and log in as IAM users with limited roles. The migrate Job and `li-admin` log in as `li_admin`, the database superuser, with a password that's stored in Secret Manager.

The way in for a person is **Cloud SQL Studio** in the Google Cloud Console, logged in as `li_admin`.

## Before you start

- **The environment must be running.** A paused environment has Cloud SQL stopped. Check with `make cloud-status` and start it with `make cloud-resume`. Pause it again afterwards (`make cloud-pause`).
- **You need these permissions on the project `lecture-indexer-511419`:** reading the secret (*Secret Manager Secret Accessor*, which a project Owner already has) and using Cloud SQL (*Cloud SQL Admin*, or Owner).

## 1. Get the `li_admin` password

In the console:

1. Open https://console.cloud.google.com and select the project **lecture-indexer-511419**.
2. Go to **Security → Secret Manager**, or search "Secret Manager" in the top bar.
3. Click **db-admin-password**.
4. On the **Versions** tab, open the **Actions** menu (⋮) of the latest enabled version and choose **View secret value**.

Or with the CLI:

```sh
gcloud secrets versions access latest --secret=db-admin-password
```

## 2. Open Cloud SQL Studio

1. In the console, go to **SQL**, then click the instance **li-pg**.
2. Choose **Cloud SQL Studio** in the instance's left menu.
3. Log in with:
   - **Database:** `li`
   - **User:** `li_admin`
   - **Password:** from step 1
4. Write queries in the editor and click **Run**.

## Useful queries

Duplicate emails, which would make migration `0003_user_admin.sql` fail. No rows means you're clear:

```sql
SELECT lower(email), count(*) FROM users GROUP BY 1 HAVING count(*) > 1;
```

Users and their roles:

```sql
SELECT id, email, role, created_at FROM users ORDER BY email;
```

Recent account changes (after migration 0003):

```sql
SELECT a.created_at, coalesce(actor.email, 'li-admin CLI') AS actor, target.email AS target, a.action, a.detail
FROM user_audit a
LEFT JOIN users actor ON actor.id = a.actor_id
LEFT JOIN users target ON target.id = a.target_id
ORDER BY a.created_at DESC LIMIT 50;
```

Which migrations have been applied:

```sql
SELECT version, applied_at FROM schema_migrations ORDER BY version;
```

## Rules

- **Read-only by default.** `li_admin` can change or drop anything, and Cloud SQL Studio runs statements right away, so there's no review and no undo. Change data through the app, `li-admin` or a migration instead.
  - If a manual fix is unavoidable, first take a backup: **SQL → li-pg → Backups → Create backup**.
  - Wrap the fix in `BEGIN; ... COMMIT;`, and check the row count before committing.
  - Note what you did and why in the pull request or the team chat.
- **Never change the schema by hand.** Schema changes go through `db/migrations/`, the release process and its approval, or the next migration may fail against a schema it doesn't expect.
- **Don't keep the password.** Don't save it in files, notes, chat or a password manager shared with others. Fetch it again when you need it.
- **If the password leaks**, rotate it. Increment the default of `db_admin_password_version` in [`variables.tf`](../../infra/terraform/envs/prod/variables.tf) and release. Terraform sets the new password in Cloud SQL and Secret Manager together. Details are in the [runbook](../runbooks/bootstrap.md), §6: don't set the version in `terraform.tfvars`.
- **Personal data.** The `users` table holds names and email addresses. Look up only what the task needs, and don't copy query results out of the console.
