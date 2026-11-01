# To do

Work we need to do that isn't scheduled in the [implementation plan](implementation-plan.md) yet. Move an item there, or delete it, once it's picked up. Optional improvements are in the [wishlist](wishlist.md).

## Finish the backup setup

From the [record of the setup](milestones/m3_technical_review/azure-backup-setup.md):

1. Run `make cloud-pause`, and confirm it takes a backup first. After `make cloud-resume`, `kubectl -n li get cronjob backup` should show `SUSPEND` as `False`.
2. Confirm the local `~/li-backup.key` was deleted with `shred -u`, after checking that an off-machine copy of `~/li-backup.key.age` still decrypts.
3. Share the encrypted key with a teammate, and the passphrase separately.
4. Put the SAS expiry, **2027-10-31**, in a calendar. `make cloud-backup-sas` renews it.
5. [Add teammates to the failure alert](runbooks/backup-and-restore.md#add-teammates-to-the-failure-alert), so a failed backup doesn't depend on one person's inbox.

## Finish the Grafana setup

From the [Grafana Cloud plan](monitoring/grafana-cloud-plan.md#how-well-know-it-works):

1. Have the team confirm [the decisions the plan asked for](monitoring/grafana-cloud-plan.md#before-we-start), especially using Grafana Labs as a third party and who owns the account.
2. Check the free tier's user limit before inviting teammates. Sources disagreed, and it may be as low as 3.
3. Check that `BlobCount` on the dashboard went up after the 2026-11-01 21:25 UTC backup.
4. Run the forced failure in the [backup runbook](runbooks/backup-and-restore.md#check-the-protections), confirm `backup_failed` rises on the dashboard, and put the CronJob back. It emails the alert channel.
5. Confirm the charts resume after `make cloud-pause` and `make cloud-resume`, with no change in Grafana.
6. Run `make cloud-grafana-credentials` again, and confirm that the old credentials stop working and both data sources still pass.
7. Put the Azure secret's expiry, **2027-11-01**, in a calendar. The same command renews it and replaces the Google key, which never expires.
8. Ask WMU IT to delete the ownerless Azure app `li-grafana`, client ID `43d8235c-798b-40c7-832c-89ac9abb73bb` ([why it exists](architecture_decision_records/0005-monitoring-on-grafana-cloud.md#consequences)). It has no owner, credentials or roles, so it's harmless.

## Finish the user-roles change (contract step)

[ADR 0002](architecture_decision_records/0002-invite-only-users-and-admin-roles.md) moved roles into the database. The release that shipped it kept two things for one release, so that the previous version still works during a rollback. **Ready to do:** it went out in `prod-2026-10-19.1`, and later releases followed:
- **The empty `PROFESSOR_EMAILS` key** in `deploy/k8s/overlays/prod/values/values.env`. The previous pods read it from `li-config`, and `kubectl rollout undo` would fail if it were missing. Delete it.
- **Search's `INSERT` on `users`** (`0002_app_roles.sql`). Sign-in now only claims invitations (an `UPDATE`), so a new migration can `REVOKE INSERT ON users FROM li_search_role`.

Do both once it's clear no rollback to that release is needed.

## Drop `users.is_superuser` (contract step)

[ADR 0003](architecture_decision_records/0003-merge-superuser-into-admin.md) merged superuser into admin. The code no longer uses the column, but the release before it still selects it, so it stayed for one release. **Ready to do:** it went out in `prod-2026-10-31.1`, and three releases followed. Once it's clear no rollback is needed:
- Add a migration: `ALTER TABLE users DROP COLUMN is_superuser`.
- Remove `test_admin_revokes_admin_from_a_former_superuser` from `services/ingest/tests/test_admin_routes.py`; it sets the column directly.

## Test the onboarding guide

Have someone who hasn't worked on the project follow [onboarding.md](onboarding.md), and fix what trips them up.

## Give teammates access to the clouds and the app

**Today:** only the project owner can use the Google Cloud and Azure accounts, and in the app, admin has to be granted account by account ([ADR 0002](architecture_decision_records/0002-invite-only-users-and-admin-roles.md); check with `make cloud-admin ARGS=list`). Teammates can't pause or resume the environment, read logs, check costs, or manage users.

Keep the teammates' email addresses **out of this repository** (it's public; see ADR 0002). Use the team's own contact list, and grant access by hand in each console.

1. **Google Cloud** (project `lecture-indexer-511419`): **IAM & Admin → IAM → Grant access**, for each teammate's Google account.
   - **Owner** if they're full co-owners of the project. That includes IAM and billing visibility.
   - Otherwise, enough for `make cloud-*`, the logs and the [database access guide](security/database-access.md): **Editor**, plus **Secret Manager Secret Accessor** on the `db-admin-password` secret only. Editor alone can't read secret values. Check that `make cloud-pause` / `cloud-resume` work for them; they change Cloud SQL and the cluster.
   - Also add each one as a **test user** on the OAuth consent screen (**Google Auth Platform → Audience**). While the app is in testing mode, Google refuses sign-in for anyone else.
2. **Azure** (subscription with `rg-li-prod` and `rg-li-backup`): invite each teammate as a guest (**Microsoft Entra ID → Users → Invite external user**). Then assign a role on the subscription or on `rg-li-prod` (**Access control (IAM) → Add role assignment**): **Contributor** to manage resources, or **Reader** to look only. Azure for Students may restrict guest invitations; if it does, note what works here.
3. **App admins**, one per teammate:
   ```sh
   make cloud-create-admin EMAIL=<their Google email>
   ```
   They then sign in with that Google account. Admin doesn't include professor: anyone who needs to create courses switches with **Your role** in the top bar. Once one admin exists, the rest can also be granted on the Admin page.
4. **GitHub:** collaborator access, and `prod` environment reviewer for anyone who will approve releases ([release-process.md](release-process.md)).

Afterwards, have each teammate confirm with `make cloud-status` and a sign-in to the app. Record who has which access somewhere outside the repo, so it can be revoked at the end of the semester.
