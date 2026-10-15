# Services

Two Flask APIs in one [uv](https://docs.astral.sh/uv/) workspace, sharing the `li_common` package.

| Package | Image | Purpose |
|---|---|---|
| `common/` (`li_common`) | — | Google ID-token auth and roles, Postgres pool, request validation, JSON errors, health checks, structured logging, `li-migrate` |
| `ingest/` | `services/ingest/Dockerfile` | Professors create courses and register YouTube lectures; captions are fetched, split into ~20 s segments, and stored |
| `search/` | `services/search/Dockerfile` | Any signed-in user lists courses and runs full-text search with timestamped deep links |

Both images listen on `:8080` and are built from the **repository root** (they also need `db/migrations`).

## Development

```sh
make install     # services/.venv (Python 3.12)
make test        # unit tests; database tests skip
make test-db     # starts the compose Postgres, runs everything
make dev-up      # full stack: ingest on :8081, search on :8082
```

Database tests use `DATABASE_URL` and create a throwaway schema per test, so any Postgres 16 you can create schemas in works.

Locally, `LI_DEV_AUTH=1` accepts `Authorization: Bearer dev:<email>` instead of a Google ID token. Emails in `PROFESSOR_EMAILS` get the professor role. The services refuse to start with dev auth inside Kubernetes.

## Configuration

| Variable | Notes |
|---|---|
| `DATABASE_URL` | In GKE this points at the Cloud SQL Auth Proxy sidecar (`127.0.0.1`) with IAM login |
| `GOOGLE_CLIENT_ID` | OAuth web client ID; the ID token's audience must match |
| `PROFESSOR_EMAILS` | Comma-separated; signing in with one grants the professor role |
| `CORS_ORIGINS` | Comma-separated frontend origins (the Static Web Apps URL) |
| `LI_DEV_AUTH` | `1` enables dev tokens; local only |
| `DB_POOL_SIZE` | Connections per gunicorn worker (default 4, matching `--threads 4`) |
| `LI_MIGRATE_GRANTS` | `li-migrate` only: `role=user,...` pairs granting the `li_ingest_role` / `li_search_role` group roles to the services' database users (Terraform output `migrate_grants`) |

Any variable can instead be given as `NAME_FILE`, a path to a file holding the value (how Secret Manager mounts secrets).

## API

Every endpoint except the health checks needs `Authorization: Bearer <Google ID token>`. Errors are JSON: `{"error": "<code>", "message": "...", ...}`.

### Ingest (professor role)

| Method | Path | Body / headers | Result |
|---|---|---|---|
| `POST` | `/ingest/courses` | `{"code": "CS6030", "title": "..."}` | `201` course; `409` duplicate code |
| `GET` | `/ingest/courses` | | your courses with `lecture_count` |
| `POST` | `/ingest/courses/{id}/lectures` | `{"video": "<YouTube URL or ID>"}` + `X-YouTube-Token: <OAuth access token>` | `201` lecture with `status: "indexed"` and `segment_count` |
| `GET` | `/ingest/lectures/{id}` | | lecture status, including `error` when `failed` |
| `DELETE` | `/ingest/lectures/{id}` | | `204` |

The YouTube access token needs the `https://www.googleapis.com/auth/youtube.force-ssl` scope (the caption endpoints accept no narrower one). It is used for that request only and never stored or logged. Registering a lecture fails with `403 not_video_owner` unless the video belongs to the signed-in account's channel, `422 no_captions` if it has no usable caption track, and `503 youtube_quota` when the API quota is exhausted. Re-registering a video re-indexes it.

### Search (any signed-in user)

| Method | Path | Result |
|---|---|---|
| `GET` | `/search/courses` | all courses with professor name and indexed `lecture_count` |
| `GET` | `/search/courses/{id}/lectures` | indexed lectures |
| `GET` | `/search/courses/{id}/segments?q=<query>&limit=20` | ranked hits |

`q` uses web-search syntax: `"lambda calculus"` for a phrase, `-word` to exclude, `or` for alternatives. Matching is stemmed, so `language` matches "languages". A hit looks like:

```json
{
  "lecture_id": 4,
  "lecture_title": "Fall Lecture 4",
  "video_id": "abcdefghijk",
  "start_seconds": 202,
  "timestamp": "03:22",
  "excerpt_html": "<mark>Lambda</mark> <mark>calculus</mark> is the basis of functional languages.",
  "url": "https://www.youtube.com/watch?v=abcdefghijk&t=202s"
}
```

`excerpt_html` is safe to render as HTML: the caption text is escaped and the only tags are `<mark>`.

### Health

`GET /healthz` (liveness, always 200) and `GET /readyz` (200 when the database answers, else 503) on both services.

## Logs and metrics

Logs are one JSON object per line for Cloud Logging. Events the monitoring dashboard builds on:

| `event` | Fields |
|---|---|
| `http_request` | `service`, `method`, `route`, `status`, `latency_ms` |
| `youtube_api_call` | `method`, `status`, `quota_units` |
| `ingest_succeeded` / `ingest_failed` | `video_id`, `lecture_id`, `segments` / `reason` |
