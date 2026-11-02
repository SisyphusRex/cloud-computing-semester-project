# Security review notes

Everything earlier work set aside for the [M3 security review](../milestones/m3_technical_review/), in one list, with the source of each note. This is the review's input, not the review. The course requires it to show identity management, access control and secrets management.

## Identity and access control

- **User administration (ADRs 0002 and 0003)** for the M3 security review: who can grant what (admins do everything on the Admin page except disable themselves or change their own admin flag; the first admin comes from `li-admin`, which needs the database-admin secret; a stolen admin session reaches the top tier), the `user_audit` trail and `user_claimed` / `sign_in_not_invited` log events, and that the admin endpoints live in the Ingest API so Search keeps its read-mostly database role. Human access to the database (Cloud SQL Studio as `li_admin`) and its rules: [database-access.md](database-access.md).
- **Who can grant which tier** ([ADR 0002](../architecture_decision_records/0002-invite-only-users-and-admin-roles.md), [ADR 0003](../architecture_decision_records/0003-merge-superuser-into-admin.md)). ADR 0002's split, where the top tier needed database-admin access, is gone: since ADR 0003, a single admin tier reaches everything from the web UI.
- **A stolen admin session reaches the top tier** ([ADR 0003](../architecture_decision_records/0003-merge-superuser-into-admin.md)). An attacker with an admin's token, which lasts about an hour, could grant admin or disable other admins, but not disable or demote the account they're using. `user_audit` records it, and `li-admin` can restore access.
- **YouTube scope.** The proposal says the professor's YouTube token is requested with a read-only scope, but `captions.list` and `captions.download` only accept `youtube.force-ssl`. The token is used for one request and never stored or logged. Correct this in the M3 security review.
- **Consent screen wording** (from the [real test's follow-ups](../milestones/m2_prototype_review/real-youtube-test.md#8-results-2026-10-18)). It tells professors the app can "see, edit, and permanently delete" their YouTube videos; explain that only GET calls are made and the token is never stored.
- **Sign-in persistence, if it's ever done** ([wishlist](../wishlist.md#keep-the-sign-in-across-page-refreshes)). Keeping the session in `sessionStorage` exposes the ID token to injected scripts until it expires; note the trade-off.
- **Leftover privileges removed** (migration `0006_contract_user_roles.sql`). Search kept `INSERT` on `users` and use of its sequence for a release after [ADR 0002](../architecture_decision_records/0002-invite-only-users-and-admin-roles.md), so a rollback would still work. Both are revoked, leaving it `SELECT` plus `UPDATE` on `users`.

## Secrets management

- **Static Web Apps deploy token** ([ADR 0001](../architecture_decision_records/0001-frontend-on-cloud-run.md)). The token, which Terraform stored in state, no longer exists.
- **Backups log in as `li_admin`** ([ADR 0004](../architecture_decision_records/0004-database-backups-to-azure.md)), the same as migrations. The CronJob's Google service account can read that password. A read-only backup user is worth considering.
- **Immutability's limit** ([ADR 0004](../architecture_decision_records/0004-database-backups-to-azure.md)). A subscription owner can remove the unlocked policy, so it protects against a stolen SAS or a mistake, not against a compromised Azure owner account.

- **Grafana Cloud's credentials** ([ADR 0005](../architecture_decision_records/0005-monitoring-on-grafana-cloud.md)). A Google service account key and an Azure client secret are held by Grafana Labs: our first long-lived credentials outside our own clouds. The key is limited to `roles/monitoring.viewer`, and never expires. The secret is limited to `Monitoring Reader` on `rg-li-backup`, and expires 2027-11-01. Neither can change anything, or read the database, secrets or backups. They're kept out of Terraform state, and the [monitoring runbook](../runbooks/monitoring.md#revoke-a-leaked-credential) covers rotating and revoking them. Rotation is scripted, but hasn't been tested.
- **Grafana admin token.** A Grafana service account token with the Admin role can read and replace data sources. It's kept encrypted on one machine, and never goes into GitHub.

## Availability and abuse

- **No rate limiting** ([wishlist](../wishlist.md#limit-requests-at-the-load-balancer)). The API sits behind a load balancer, not an API gateway, and nothing limits how many requests a client can send. Most routes need a sign-in, but those requests still reach the pods and the database, and a signed-in professor could use up the YouTube quota (10,000 units a day; one registration costs 252). A flood could also scale the pods up to their limits, and raise costs. Cloud Armor could add a limit by IP address on this load balancer.

## Browser security

- **CSP** ([ADR 0001](../architecture_decision_records/0001-frontend-on-cloud-run.md)). It's now set by nginx, and its `connect-src` names the API origin at build time.

## Monitoring and response

- **Only backup failures raise an alert** ([dashboard reference](../monitoring/dashboard.md)). "Database backup failed" is the one alert, and it only fires when a backup Job gives up. Nothing alerts on the site or API going down, on application errors, or on a backup that never ran. Those show on the Grafana dashboard, if someone looks, except application errors: `app_errors` is recorded, but no panel shows it. So an outage or an attack could go unnoticed until someone opens the dashboard.
