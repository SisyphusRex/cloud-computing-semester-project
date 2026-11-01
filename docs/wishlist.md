# Wishlist

Optional improvements. The project works without them, and nothing depends on them, so pick one up only if it's worth the time. Work we need to do is in the [to-do list](todo.md). Move an item there once the team decides to do it.

## Tell users when the environment is paused

**Today:** while the environment is paused (`make cloud-pause`), the Cloud Run frontend still loads and Google sign-in still works, because neither depends on our infrastructure. Every API call then fails, and the app shows the generic "Could not reach the server." ([`client.ts`](../frontend/src/api/client.ts), `network_error`). To a teammate or grader that looks like a bug.

Two improvements, independent of each other:

1. **A clearer message for an unreachable API (small).** When the API can't be reached at all (`network_error`), show something like *"The service is paused to save cost. Ask the team to resume it."* instead of the generic error, at least on the first request after sign-in. Keep the generic wording for other failures. Add a vitest case.
2. **A maintenance banner while paused (more moving parts).** Show a banner on every page while the environment is paused, before anyone signs in.
   - `make cloud-pause` sets a flag the frontend can read, and `make cloud-resume` clears it as its last step, next to the namespace annotation.
   - The flag could be a Cloud Run environment variable read at container start (`gcloud run services update li-frontend --update-env-vars LI_PAUSED=1`, served by nginx as a small `/status.json`), or a static file in a public bucket.
   - Keep other tools from clearing the flag: releases and `rollback.yml` already don't deploy while paused, but Terraform would remove an environment variable set by `gcloud`. Add `template[0].containers[0].env` to `ignore_changes` in [`modules/cloud-run-frontend`](../infra/terraform/modules/cloud-run-frontend/main.tf), or use the bucket file instead.
   - Update `cloud-power.sh`'s step list and the runbook.

## Limit requests at the load balancer

**Today:** the API sits behind a load balancer, not an API gateway. It routes requests and handles HTTPS, and the Flask services check sign-ins. Nothing limits how many requests a client can send, so a flood would reach the pods, and registering lectures could use up the YouTube quota (10,000 units a day; one registration costs 252).

**Option:** add a [Cloud Armor](https://cloud.google.com/armor/docs) security policy with a rate-limiting rule, which works on this load balancer without adding a gateway.

- Create the policy in `envs/prod`, and attach it through the `BackendConfig` on each service.
- Start in preview mode, to see what it would block before it blocks anything, and check its cost first.
- Limit by IP address. Per-user limits would need the Flask services, because only they know who's signed in.
- `make cloud-pause` deletes the load balancer, so confirm the policy returns on `make cloud-resume`.
- If done, note it in the M3 security review. If not, note the lack of rate limiting there.

## Keep the sign-in across page refreshes

**Today:** the session (the Google ID token, or the dev token) lives only in React state ([`AuthContext.tsx`](../frontend/src/auth/AuthContext.tsx)). Refreshing the page signs you out. In production that means another Google sign-in after every reload; when testing locally, it means typing the account again. This was deliberate: a token in browser storage can be read by any script that gets onto the page.

**Option:** keep the session in `sessionStorage`, restore it on load, and clear it on sign-out and when the token expires (the existing timer). `sessionStorage` is limited to one tab and cleared when the tab closes, unlike `localStorage`.

- **Risk:** an injected script could read the ID token and use it against the APIs until it expires (about an hour). The nginx Content-Security-Policy (`script-src 'self'` plus Google's sign-in script, in [`security-headers.conf`](../frontend/nginx/security-headers.conf)) makes that unlikely, but it's still more exposure than memory.
- **Don't persist the YouTube access token.** It can manage the professor's channel; keep it in memory as now.
- If done, add a vitest case (restored on load, cleared on sign-out and on expiry), and note the trade-off in the M3 security review.

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

## Tighter deep links

Links open at the start of a window of up to ~20 s, so a word can play ~10-20 s in ([test results](milestones/m2_prototype_review/real-youtube-test.md#8-results-2026-10-18)). Shorter windows (`max_ms` in `merge_segments`) would tighten them, at the cost of phrases split across segments.

## Replace the caption test fixture with a real download

`services/ingest/tests/fixtures/lecture4.vtt` is modeled on YouTube's usual ASR format, because the raw WebVTT wasn't captured during the test. Real captions parsed cleanly, but the fixture is unconfirmed byte for byte. Next time, trim a real `captions.download` response into the fixture, and update `test_captions.py` if they differ.

## Delete the older on-demand database backups

Each [first-release attempt](milestones/m2_prototype_review/first-deployment.md#results-2026-10-18) that reached the migrations took a backup, so `li-pg` has three on-demand backups from 2026-10-18 (cents per month; the older two can go).
