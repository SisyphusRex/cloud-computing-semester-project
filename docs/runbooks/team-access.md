# Team access

How to give someone access to the clouds and the app. Our current teammates already have it. A new person needs this to pause or resume the environment, read logs, check costs or manage users. None of it is needed to run the app locally.

Keep teammates' email addresses **out of this repository** (it's public; see ADR 0002). Use the team's own contact list, and grant access by hand in each console.

1. **Google Cloud** (project `lecture-indexer-511419`): **IAM & Admin → IAM → Grant access**, for their Google account.
   - **Owner** if they're full co-owners of the project. That includes IAM and billing visibility.
   - Otherwise, enough for `make cloud-*`, the logs and the [database access guide](../security/database-access.md): **Editor**, plus **Secret Manager Secret Accessor** on the `db-admin-password` secret only. Editor alone can't read secret values. Check that `make cloud-pause` / `cloud-resume` work for them; they change Cloud SQL and the cluster.
   - Also add them as a **test user** on the OAuth consent screen (**Google Auth Platform → Audience**). While the app is in testing mode, Google refuses sign-in for anyone else.
2. **Azure** (subscription with `rg-li-prod` and `rg-li-backup`): invite them as a guest (**Microsoft Entra ID → Users → Invite external user**). Then assign a role on the subscription or on `rg-li-prod` (**Access control (IAM) → Add role assignment**): **Contributor** to manage resources, or **Reader** to look only. Azure for Students may restrict guest invitations; if it does, note what works here.
3. **App admin:**
   ```sh
   make cloud-create-admin EMAIL=<their Google email>
   ```
   They then sign in with that Google account. Admin doesn't include professor: anyone who needs to create courses switches with **Your role** in the top bar. Once one admin exists, the rest can also be granted on the Admin page.
4. **GitHub:** collaborator access, and `prod` environment reviewer for anyone who will approve releases ([release-process.md](../release-process.md)).

Afterwards, have them confirm with `make cloud-status` and a sign-in to the app. Record who has which access somewhere outside the repo, so it can be revoked at the end of the semester.
