# Real Google and YouTube test

The automated tests mock Google sign-in and the YouTube API. This test runs the local stack against both for real. It takes about 20 minutes and needs no billing account.

**You need:**
- A Google account whose YouTube channel has a video with **auto-generated** captions. YouTube creates them some time after upload. YouTube Studio → Subtitles shows an "English (automatic)" track once they exist. An unlisted video works.
- Optionally, a second video of yours with only uploaded captions, and the URL of any video you don't own.
- The local setup from [local-development.md](../local-development.md) working (`make dev-up`, `make frontend-dev`).

## 1. Google Cloud Console (once)

Do this in the GCP project Terraform will use. Any project works, but this one reuses the OAuth client in production; Terraform can't create the client (runbook step 5).

1. **APIs & Services → Library**: enable **YouTube Data API v3**. API calls count against this project's free daily quota.
2. **OAuth consent screen**:
   - User type **External**, publishing status **Testing**.
   - Scopes: `openid`, `email`, `profile`, `https://www.googleapis.com/auth/youtube.force-ssl`.
   - **Test users**: add every tester's Google account. Others can't sign in while the app is in Testing.
3. **Credentials → Create credentials → OAuth client ID**:
   - Type **Web application**.
   - Authorized JavaScript origin `http://localhost:5173`. No redirect URI is needed.
   - Copy the client ID. It isn't a secret.

## 2. Start the APIs with real Google auth

`docker-compose.yml` hardcodes dev auth. The override `docker-compose.google.yml` (in the repo root) turns it off for `migrate`, `ingest` and `search`, and reads `GOOGLE_CLIENT_ID` from `.env`. Create `.env` in the repo root; it's git-ignored, and Compose reads it itself, so the value also works under `sudo`:

```
GOOGLE_CLIENT_ID=<id>.apps.googleusercontent.com
```

Then start the stack (prefix `sudo` if your user isn't in the `docker` group):

```sh
make dev-down                       # stop a dev-auth stack if one is running
docker compose -f docker-compose.yml -f docker-compose.google.yml up --build -d
docker compose run --rm --entrypoint li-admin seed add-user <your Google email> --role professor --admin
docker compose logs -f ingest       # leave running in a second terminal
```

Sign-in is invite-only ([ADR 0002](../architecture_decision_records/0002-invite-only-users-and-admin-roles.md)), so invite every account you'll test with. `create-admin` alone isn't enough here: an admin isn't a professor unless the role says so. Invite a student account with `--role student`.

Don't run `make smoke` against this stack. It signs in with `dev:` tokens, which are now rejected.

## 3. Start the frontend with Google sign-in

In `frontend/.env.local`:

```
VITE_DEV_AUTH=0
VITE_GOOGLE_CLIENT_ID=<same id>
VITE_API_BASE=
```

Then run `make frontend-dev` and open http://localhost:5173. Vite reads `.env.local` only at startup, so restart it after editing.

## 4. Test cases

| # | Do | Expect |
|---|---|---|
| 1 | Sign in with Google | Signed in. Because the app is in Testing, Google shows an "unverified app" warning; continue. |
| 2 | Open **Manage** | The page loads. A student view means your account's role isn't `professor`. |
| 3 | Create a course, register your video with auto-captions; grant the YouTube permission when asked | Lecture `indexed` with a segment count; the log shows `youtube_api_call` lines and `ingest_succeeded` |
| 4 | As any user, search the course for a word you say in the video | A hit with a highlighted excerpt; the link opens YouTube within a few seconds before the word |
| 5 | Register the same video again | Still `indexed`, same segment count (re-index, no duplicates) |
| 6 | Register a video you don't own | "You can only register videos from your own YouTube channel" (`403 not_video_owner`) |
| 7 | (Optional) Register your video with only uploaded captions | Lecture `failed`: "The video has no auto-generated captions" (`422 no_captions`) |
| 8 | Delete a lecture | It disappears, and search no longer finds it |

To see what was stored, run:

```sh
docker compose exec db psql -U li -d li -c \
  "select start_ms/1000 as sec, left(text, 80) from segments order by start_ms limit 15;"
```

The text should read as clean running speech: no repeated phrases, no `<c>` or timestamp tags. The times should match the video.

## 5. If something fails

| Symptom | Likely cause |
|---|---|
| Google popup: `Error 400: redirect_uri_mismatch` or "origin not allowed" | `http://localhost:5173` is missing from the OAuth client's JavaScript origins. Changes can take a few minutes to apply. |
| `Error 403: access_denied` at sign-in | Your account isn't a test user on the consent screen |
| `401 Invalid or expired ID token` | `GOOGLE_CLIENT_ID` in `.env` doesn't match `VITE_GOOGLE_CLIENT_ID`, or the APIs weren't recreated after you edited `.env` (run `up -d` again) |
| `400 youtube_token_invalid` | The YouTube permission was declined, or the scope isn't on the consent screen |
| `403 not_video_owner` on your own video | The account owns the video but `captions.download` refused the auto-generated track. See "Record" below. If the account has several channels (brand accounts), pick the video's channel when you sign in. |
| `502 youtube_error` mentioning the API | YouTube Data API v3 isn't enabled in the project |
| `422 no_captions` on a video that should have auto-captions | The ASR track isn't ready yet, or it's disabled for the video in YouTube Studio |

## 6. Finish

To finish, run `docker compose -f docker-compose.yml -f docker-compose.google.yml down`, then set `VITE_DEV_AUTH=1` again to return to dev sign-in. You can keep `.env` and the override file for next time.
