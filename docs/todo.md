# To do

Open work that isn't scheduled in the [implementation plan](implementation-plan.md) yet. Move an item there, or delete it, once it's picked up.

## Finish the backup setup

From the [record of the setup](milestones/m3_technical_review/azure-backup-setup.md):

1. On 2026-11-01, run `make cloud-restore ARGS="list"` and confirm a backup from around 08:00 UTC. The environment has to be running at that time.
2. Run `make cloud-pause`, and confirm it takes a backup first. After `make cloud-resume`, `kubectl -n li get cronjob backup` should show `SUSPEND` as `False`.
3. Confirm the local `~/li-backup.key` was deleted with `shred -u`, after checking that an off-machine copy of `~/li-backup.key.age` still decrypts.
4. Share the encrypted key with a teammate, and the passphrase separately.
5. Put the SAS expiry, **2027-10-31**, in a calendar. `make cloud-backup-sas` renews it.
6. [Add teammates to the failure alert](runbooks/backup-and-restore.md#add-teammates-to-the-failure-alert), so a failed backup doesn't depend on one person's inbox.

## Delete the older on-demand database backups

Each [first-release attempt](milestones/m2_prototype_review/first-deployment.md#results-2026-10-18) that reached the migrations took a backup, so `li-pg` has three on-demand backups from 2026-10-18 (cents per month; the older two can go).

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

## Tell users when the environment is paused

**Today:** while the environment is paused (`make cloud-pause`), the Cloud Run frontend still loads and Google sign-in still works, because neither depends on our infrastructure. Every API call then fails, and the app shows the generic "Could not reach the server." ([`client.ts`](../frontend/src/api/client.ts), `network_error`). To a teammate or grader that looks like a bug.

Two improvements, independent of each other:

1. **A clearer message for an unreachable API (small).** When the API can't be reached at all (`network_error`), show something like *"The service is paused to save cost. Ask the team to resume it."* instead of the generic error, at least on the first request after sign-in. Keep the generic wording for other failures. Add a vitest case.
2. **A maintenance banner while paused (more moving parts).** Show a banner on every page while the environment is paused, before anyone signs in.
   - `make cloud-pause` sets a flag the frontend can read, and `make cloud-resume` clears it as its last step, next to the namespace annotation.
   - The flag could be a Cloud Run environment variable read at container start (`gcloud run services update li-frontend --update-env-vars LI_PAUSED=1`, served by nginx as a small `/status.json`), or a static file in a public bucket.
   - Keep other tools from clearing the flag: releases and `rollback.yml` already don't deploy while paused, but Terraform would remove an environment variable set by `gcloud`. Add `template[0].containers[0].env` to `ignore_changes` in [`modules/cloud-run-frontend`](../infra/terraform/modules/cloud-run-frontend/main.tf), or use the bucket file instead.
   - Update `cloud-power.sh`'s step list and the runbook.

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

## Revoke admins with `li-admin`

**Today:** an admin can revoke another admin on the Admin page ([ADR 0003](architecture_decision_records/0003-merge-superuser-into-admin.md)), but `li-admin` can only grant. If only one admin is left, or nobody can sign in, removing the flag takes a hand-written SQL `UPDATE` as `li_admin` ([database access guide](security/database-access.md)). That writes no `user_audit` row, so the change leaves no record.

**Goal:** `li-admin revoke-admin EMAIL` in [`admin.py`](../services/common/src/li_common/admin.py):
- It clears `is_admin` through `users.update(..., actor_id=None)`, so the change is audited like the other CLI commands.
- It refuses to remove the **last** admin, since nobody could grant admin from the app after that. `--force` overrides this.
- It's safe to re-run, and errors clearly on an unknown email.
- In prod: `make cloud-admin ARGS="revoke-admin EMAIL"`. `scripts/cloud-admin.sh` passes the arguments through, so no new script is needed.
- Tests in `services/common/tests/test_admin_cli.py`: revoke, the last-admin guard, and the audit row.
- Docs: the `li-admin` list in `services/README.md`, and the database access guide, which should point to this command instead of SQL.
- Optionally, also `disable`, so the CLI can undo everything it can grant.

## Optional

Ideas worth considering. Nothing depends on them; pick one up only if it's worth the time.

### Tighter deep links

Links open at the start of a window of up to ~20 s, so a word can play ~10-20 s in ([test results](milestones/m2_prototype_review/real-youtube-test.md#8-results-2026-10-18)). Shorter windows (`max_ms` in `merge_segments`) would tighten them, at the cost of phrases split across segments.

### Replace the caption test fixture with a real download

`services/ingest/tests/fixtures/lecture4.vtt` is modeled on YouTube's usual ASR format, because the raw WebVTT wasn't captured during the test. Real captions parsed cleanly, but the fixture is unconfirmed byte for byte. Next time, trim a real `captions.download` response into the fixture, and update `test_captions.py` if they differ.

### Keep the sign-in across page refreshes

**Today:** the session (the Google ID token, or the dev token) lives only in React state ([`AuthContext.tsx`](../frontend/src/auth/AuthContext.tsx)). Refreshing the page signs you out. In production that means another Google sign-in after every reload; when testing locally, it means typing the account again. This was deliberate: a token in browser storage can be read by any script that gets onto the page.

**Option:** keep the session in `sessionStorage`, restore it on load, and clear it on sign-out and when the token expires (the existing timer). `sessionStorage` is limited to one tab and cleared when the tab closes, unlike `localStorage`.

- **Risk:** an injected script could read the ID token and use it against the APIs until it expires (about an hour). The nginx Content-Security-Policy (`script-src 'self'` plus Google's sign-in script, in [`security-headers.conf`](../frontend/nginx/security-headers.conf)) makes that unlikely, but it's still more exposure than memory.
- **Don't persist the YouTube access token.** It can manage the professor's channel; keep it in memory as now.
- If done, add a vitest case (restored on load, cleared on sign-out and on expiry), and note the trade-off in the M3 security review.
