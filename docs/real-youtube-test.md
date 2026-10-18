# Real Google/YouTube test: progress log

My run of the [real Google/YouTube test](implementation-plan.md#next-real-googleyoutube-test-free-before-deploying). That section has the general runbook and troubleshooting; this file tracks what I've done. Tick boxes as I go.

**Accounts** (real addresses are kept out of this file; the professor's is in `.env`)
- **Channel account**: owns the YouTube channel and the test video; signs in as the professor.
- **Student account**: a second Google account, for checking the student view.

**OAuth client ID:** `294292796743-npo1ene9euu5v10tundn5inb1sval8n4.apps.googleusercontent.com` (not a secret)

## 1. Google Cloud Console (done 2026-10-18)

- [x] Enabled **YouTube Data API v3** (APIs & Services → Library)
- [x] Google Auth Platform → **Get started** (https://console.cloud.google.com/auth/overview)
  - App name `Lecture Indexer`, support email, Audience **External**, contact email, accepted the policy, **Create**
- [x] **Audience**: publishing status **Testing** (not published); test users added:
  - [x] student account
  - [x] channel account
- [x] **Data Access** → Add or remove scopes, then **Update** and **Save**:
  - `openid`, `.../auth/userinfo.email`, `.../auth/userinfo.profile` (non-sensitive)
  - `https://www.googleapis.com/auth/youtube.force-ssl` (sensitive; expected)
- [x] **Clients** → Create client: Web application, JavaScript origin `http://localhost:5173`, no redirect URIs; copied the client ID (didn't download the secret)

## 2. Local config files (done 2026-10-18)

- [x] `.env` (repo root, git-ignored):
  ```
  GOOGLE_CLIENT_ID=294292796743-npo1ene9euu5v10tundn5inb1sval8n4.apps.googleusercontent.com
  PROFESSOR_EMAILS=<channel account email>
  ```
- [x] `docker-compose.google.yml` (repo root, committed): turns off dev auth and passes the two values above to `migrate`, `ingest` and `search`
- [x] `frontend/.env.local`: `VITE_DEV_AUTH=0`, `VITE_GOOGLE_CLIENT_ID=<client ID>`
- [x] Checked with `docker compose -f docker-compose.yml -f docker-compose.google.yml config`: all three services get the client ID, `LI_DEV_AUTH: "0"` and the professor email

## 3. Start the stack

Terminal 1, the APIs:

```sh
cd ~/wmu/6030/cloud-computing-semester-project
sudo docker compose down
sudo docker compose -f docker-compose.yml -f docker-compose.google.yml up --build -d
curl -s localhost:8081/readyz; echo; curl -s localhost:8082/readyz
```

- [x] `db`, `ingest`, `search` running; `migrate` exited
- [x] Both `readyz` calls answer OK

Terminal 2, the Ingest log (leave running):

```sh
sudo docker compose logs -f ingest
```

Terminal 3, the frontend (leave running):

```sh
cd ~/wmu/6030/cloud-computing-semester-project
make frontend-dev
```

- [ ] http://localhost:5173 loads

After editing `.env`, run the `up -d` command again; after editing `frontend/.env.local`, restart `make frontend-dev`.

## 4. Test cases

| # | Do | Expect | Result |
|---|---|---|---|
| 1 | Sign in with Google as the channel account; click **Continue** on "Google hasn't verified this app" | Signed in | |
| 2 | Open **Manage** | Manage page loads (student view = email not in `PROFESSOR_EMAILS`) | |
| 3 | Create a course (e.g. `CS6030` / "Cloud Computing"); register my video with auto-captions; in the YouTube popup, pick the channel that owns it and allow | Lecture **indexed** with a segment count; log shows `youtube_api_call` lines, then `ingest_succeeded` | |
| 4 | Search the course for a word I say in the video; click the result | Highlighted excerpt; YouTube opens a few seconds before the word | |
| 5 | Register the same video again | Still indexed, same segment count | |
| 6 | Register a video I don't own | "You can only register videos from your own YouTube channel" | |
| 7 | (Optional) Register my video with only uploaded captions | Lecture failed: "The video has no auto-generated captions" | |
| 8 | Delete a lecture | Gone from the list; search no longer finds it | |
| 9 | Sign out; sign in as the student account; search the course | Student view, no Manage page; search works | |

Video used: <!-- URL, length -->

Check what was stored after case 3:

```sh
sudo docker compose exec db psql -U li -d li -c \
  "select start_ms/1000 as sec, left(text, 80) from segments order by start_ms limit 15;"
```

- [ ] Text is clean running speech: no repeated phrases, no `<c>` or timestamp tags
- [ ] Times match the video

## 5. Findings

Copy the conclusions into the "Results" note in the implementation plan when done.

- **Does `captions.download` serve the auto-generated track?** (case 3; a `403 not_video_owner` on my own video means no)
- **Does the real VTT match `services/ingest/tests/fixtures/lecture4.vtt`?** (word-timing tags, rolling lines, `" "` line after each timing)
- **Deep-link accuracy** (seconds between the link's start and the word):
- **Other surprises / errors:**

## 6. Clean up

```sh
sudo docker compose -f docker-compose.yml -f docker-compose.google.yml down
```

- [ ] Set `VITE_DEV_AUTH=1` in `frontend/.env.local` to return to dev sign-in (keep `.env` and the override for next time)
