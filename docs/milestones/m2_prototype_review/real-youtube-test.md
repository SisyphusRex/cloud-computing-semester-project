# Real Google/YouTube test: progress log

My run of the [real Google/YouTube test](../../implementation-plan.md#next-real-googleyoutube-test-free-before-deploying). That section has the general runbook and troubleshooting; this file tracks what I've done. Tick boxes as I go.

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
| 1 | Sign in with Google as the channel account; click **Continue** on "Google hasn't verified this app" | Signed in | ✅ 2026-10-18 |
| 2 | Open **Manage** | Manage page loads (student view = email not in `PROFESSOR_EMAILS`) | ✅ 2026-10-18 |
| 3 | Create a course (e.g. `CS6030` / "Cloud Computing"); register my video with auto-captions; in the YouTube popup, pick the channel that owns it and allow | Lecture **indexed** with a segment count; log shows `youtube_api_call` lines, then `ingest_succeeded` | ✅ 2026-10-18: "Welcome to Michigan" indexed, 37 segments |
| 4 | Search the course for a word I say in the video; click the result | Highlighted excerpt; YouTube opens a few seconds before the word | ✅ 2026-10-18: searched "Concourse", one hit at `t=94s`; the word comes ~10 s after the jump |
| 5 | Register the same video again | Still indexed, same segment count | ✅ 2026-10-18: still indexed, 37 segments; `count(*)` on segments = 37 |
| 6 | Register a video I don't own | "You can only register videos from your own YouTube channel" | ✅ 2026-10-18: `403`; log shows only `videos.list` + `channels.list` (2 quota units), then `ingest_failed` `not_video_owner` with `lecture_id: null` |
| 7 | (Optional) Register my video with only uploaded captions | Lecture failed: "The video has no auto-generated captions" | ⏭️ Skipped 2026-10-18: no such video on the channel (covered by `test_uploaded_tracks_are_ignored` and the route test) |
| 8 | Delete a lecture | Gone from the list; search no longer finds it | ✅ 2026-10-18: deleted; search for "Concourse" returned no results; `count(*)` on segments = 0 (cascade). Video re-registered afterwards for case 9 |
| 9 | Sign out; sign in as the student account; search the course | Student view, no Manage page; search works |  ✅ 2026-10-18: no Manage page or link; "Concourse" found, link plays at 1:34 |

Video used: "Welcome to Michigan" <!-- URL, length -->

Check what was stored after case 3:

```sh
sudo docker compose exec db psql -U li -d li -c \
  "select start_ms/1000 as sec, left(text, 80) from segments order by start_ms limit 15;"
```

- [x] Text is clean running speech: no repeated phrases, no `<c>` or timestamp tags (2026-10-18: clean; see findings for `[Music]`)
- [x] Times look plausible: windows start ~15–20 s apart; short segments at 129–195 s match music-only stretches (spot-check against the video in case 4)

## 5. Findings

Copy the conclusions into the "Results" note in the implementation plan when done.

- **Does `captions.download` serve the auto-generated track?** (case 3; a `403 not_video_owner` on my own video means no)
  - **Yes** (2026-10-18): case 3 indexed 37 segments, and only ASR tracks are ever selected.
- **Does the real VTT match `services/ingest/tests/fixtures/lecture4.vtt`?** (word-timing tags, rolling lines, `" "` line after each timing)
  - **Parses the same** (2026-10-18): no tags or rolling repeats survive in the stored text, so the parser handles the real format. The raw VTT wasn't captured, so the fixture is still unconfirmed byte for byte.
  - ASR inserts sound tags like `[Music]`; they are indexed as words, and some segments are only `[Music]`. Fixed afterwards: `captions.py` now drops `[...]` tags and skips cues left empty.
  - Repeated words ("the the the the the" at ~0:20) are kept; dedup removes only whole repeated lines. Probably the speaker's stammer; check in the video.
- **Deep-link accuracy** (seconds between the link's start and the word): ~10 s early ("Concourse", 2026-10-18). Expected: links open at the start of a window of up to ~20 s, so a word mid-window plays ~10 s in. Possible follow-up: shorter windows (`max_ms` in `merge_segments`) for tighter links, at the cost of phrases split across segments.
- **Other surprises / errors:**
  - gunicorn 26 logged `Control server error: Permission denied: '/home/app'`; fixed with `--no-control-socket` (`bcd1e71`).
  - A full registration costs 252 quota units (1 + 1 + 50 + 200) and took 650 ms; the default daily quota of 10,000 allows ~39 registrations a day.

## 6. Clean up

```sh
sudo docker compose -f docker-compose.yml -f docker-compose.google.yml down
```

- [x] Stack stopped (2026-10-18); `VITE_DEV_AUTH=1` set in `frontend/.env.local` to return to dev sign-in (kept `.env` and the override for next time)
