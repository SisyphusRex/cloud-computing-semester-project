# The Grafana dashboard

What the Lecture Indexer dashboard shows, and where each number comes from. To change or look after it, see the [monitoring runbook](../runbooks/monitoring.md). For why it's built this way, see [ADR 0005](../architecture_decision_records/0005-monitoring-on-grafana-cloud.md).

The source of truth is `infra/terraform/grafana/dashboards/lecture-indexer.json`. If this page and that file disagree, the file is right.

## How the data gets there

```
                       ┌── Cloud Monitoring ◄── GKE, Cloud Run, Cloud SQL, load balancer
Grafana Cloud ─ query ─┤                    ◄── uptime checks
                       │                    ◄── log-based metrics ◄── application logs
                       └── Azure Monitor    ◄── backup storage account
```

Grafana stores no metrics of its own. Each time a panel refreshes, it queries one of two data sources, using a read-only credential:

| Data source | UID | Used for |
|---|---|---|
| Google Cloud Monitoring | `li-gcp` | Everything except the Azure row |
| Azure Monitor | `li-azure` | The Azure row |

The dashboard refreshes every 5 minutes, and its default range is the last 7 days. Most panels set their own shorter range and ignore that setting, as noted below. Only the Backups and Azure rows use it.

Numbers come from three kinds of source:

- **Built-in metrics** that Google and Azure record by themselves.
- **Log-based metrics** that we define in `infra/terraform/modules/monitoring/main.tf`. Cloud Logging counts the log lines matching a filter. They only count from when they were created, so they have no earlier history.
- **Uptime checks,** also in that file. Google sends a real HTTPS request every 5 minutes from 3 US regions, and records whether it passed.

## How to read a Google query

Each Google panel sets the same four things:

| Setting | What it does | Example |
|---|---|---|
| Metric and filters | Which series to read | `run.googleapis.com/request_count`, for `li-frontend` |
| Aligner | Turns each series into one value per time period | `ALIGN_RATE` gives requests per second |
| Reducer | Combines several series into one | `REDUCE_SUM` adds them up |
| Period | The length of each time period | `3600s` is one bar per hour. `cloud-monitoring-auto` lets Grafana choose from the time range |

The aligners and reducers used here:

| Name | Result |
|---|---|
| `ALIGN_MEAN` | The average in each period |
| `ALIGN_SUM` | The total in each period |
| `ALIGN_RATE` | The change per second |
| `ALIGN_PERCENTILE_95`, `ALIGN_PERCENTILE_50` | The 95th percentile, or the median |
| `ALIGN_FRACTION_TRUE` | The share of checks that passed, from 0 to 1 |
| `REDUCE_SUM`, `REDUCE_MEAN`, `REDUCE_MAX`, `REDUCE_MIN` | The total, average, highest or lowest across series |
| `REDUCE_COUNT` | How many series have a value, which is how pods are counted |

## Panels

Hover over a panel's **ⓘ** icon to see where its data comes from, how far behind it runs, and what it counts.

Metric names are shortened where the prefix is obvious. `user/<name>` means `logging.googleapis.com/user/<name>`.

### Health

Six Up or Down tiles. A tile with no data shows Down.

| Tile | Metric | Filter | Aligner, reducer, period | Time range | Up when |
|---|---|---|---|---|---|
| Database | `cloudsql.googleapis.com/database/up` | None | `ALIGN_MEAN`, `REDUCE_MIN`, 300s | 15 min | Latest value is at least 0.5 |
| Backups | `user/backup_succeeded` | None | `ALIGN_SUM`, `REDUCE_SUM`, 3600s | 26 h | Total is at least 1 |
| Frontend | `monitoring.googleapis.com/uptime_check/check_passed` | Host is the Cloud Run address | `ALIGN_FRACTION_TRUE`, `REDUCE_MEAN`, 300s | 15 min | At least half of the latest checks passed |
| Load balancer | `monitoring.googleapis.com/uptime_check/check_passed` | Host is the API address | `ALIGN_FRACTION_TRUE`, `REDUCE_MEAN`, 300s | 15 min | At least half of the latest checks passed |
| Ingest pods | `kubernetes.io/container/uptime` | [Pod filter](#pod-filter), `ingest-.*` | `ALIGN_MEAN`, `REDUCE_COUNT`, 60s | 15 min | Latest count is at least 1 |
| Search pods | `kubernetes.io/container/uptime` | [Pod filter](#pod-filter), `search-.*` | `ALIGN_MEAN`, `REDUCE_COUNT`, 60s | 15 min | Latest count is at least 1 |

These tiles have limits:

- **Load balancer** only shows that it answers `/healthz`, not that the API works.
- **Ingest pods and Search pods** can show Up while a pod is crash-looping, because a restarting pod still reports.
- **Everything can show Up while requests are failing.** The dashboard has no error chart. The `app_errors` metric exists, but no panel shows it.

### Frontend (Cloud Run)

Both panels show the last 10 minutes, filter on `service_name = li-frontend`, and include the uptime checks' requests.

| Panel | Metric | Aligner, reducer | Grouped by |
|---|---|---|---|
| Requests by status | `run.googleapis.com/request_count` | `ALIGN_RATE`, `REDUCE_SUM` | `response_code_class` |
| Response time, p95 | `run.googleapis.com/request_latencies` | `ALIGN_PERCENTILE_95`, `REDUCE_MAX` | None |

### API (load balancer)

Both panels show the last 10 minutes. They cover the whole load balancer, so they include the uptime checks' requests, and anything that never reached a pod. A 502 from the load balancer appears here even though the app didn't log it.

| Panel | Metric | Aligner, reducer | Grouped by |
|---|---|---|---|
| Requests by status | `loadbalancing.googleapis.com/https/request_count` | `ALIGN_RATE`, `REDUCE_SUM` | `response_code_class` |
| Response time, p95 | `loadbalancing.googleapis.com/https/total_latencies` | `ALIGN_PERCENTILE_95`, `REDUCE_MAX` | None |

### GKE

| Panel | Metric | Filter | Aligner, reducer, period | Time range |
|---|---|---|---|---|
| Ingest pods | `kubernetes.io/container/uptime` | [Pod filter](#pod-filter), `ingest-.*` | `ALIGN_MEAN`, `REDUCE_COUNT`, 60s | 10 min |
| Search pods | `kubernetes.io/container/uptime` | [Pod filter](#pod-filter), `search-.*` | `ALIGN_MEAN`, `REDUCE_COUNT`, 60s | 10 min |

The vertical axes run to each service's autoscaling limit: 4 for `ingest`, and 6 for `search`.

GKE metrics arrive a few minutes late, so the line can stop short of the right edge. The count can also be briefly too high during a release, while old and new pods overlap.

#### Pod filter

`namespace_name = li`, `container_name = app`, and `pod_name` matching the pattern. Both APIs name their container `app`, so the pod name is what tells them apart. The query counts how many pods report a value, because we do not collect a pod-count metric.

### Cloud SQL

All four panels show the last 10 minutes.

| Panel | Metric, under `cloudsql.googleapis.com/database/` | Filter | Aligner, reducer |
|---|---|---|---|
| CPU | `cpu/utilization` | None | `ALIGN_MEAN`, `REDUCE_MEAN` |
| Memory | `memory/components` | One query each for `component = Usage` and `Cache` | `ALIGN_MEAN`, `REDUCE_MEAN` |
| Disk | `disk/utilization` | None | `ALIGN_MEAN`, `REDUCE_MEAN` |
| Connections | `postgresql/num_backends` | `database = li` | `ALIGN_MEAN`, `REDUCE_SUM` |

Memory stacks Usage, then Cache on top, on a 0 to 100% axis. Free is the gap above them. They're two queries because Grafana stacks in query order, and a single query comes back alphabetically. Usage is what the database needs, and Cache is spare memory it can give back, so watch Usage. We don't chart `memory/utilization`, because on this instance `usage` always equals `quota`, so it stays at 100% whatever the real use is.

### Ingestion, Search and Backups

These are bars from log-based metrics, using `ALIGN_SUM` and `REDUCE_SUM`, except Backup size. The Ingestion and Search rows show one bar per minute over the last 10 minutes, so they're usually empty unless someone just used the app. The Backups row shows one bar per hour over the dashboard's range.

| Row | Panel | Metric | Log filter |
|---|---|---|---|
| Ingestion | Lectures ingested | `user/ingest_succeeded` | `jsonPayload.event="ingest_succeeded"` |
| Ingestion | Ingest failures | `user/ingest_failed` | `jsonPayload.event="ingest_failed"` |
| Search | Searches | `user/searches` | [Search filter](#search-filter), `jsonPayload.status=200` |
| Search | Search failures | `user/search_failed` | [Search filter](#search-filter), `jsonPayload.status>=500` |
| Backups | Backups succeeded | `user/backup_succeeded` | `jsonPayload.event="backup_succeeded"` |
| Backups | Backups failed | `user/backup_failed` | `jsonPayload.event="backup_failed"` |
| Backups | Backup size | `user/backup_bytes` | `jsonPayload.event="backup_succeeded"`, reading `jsonPayload.bytes` |

**Backup size** uses `ALIGN_PERCENTILE_50` and `REDUCE_MAX`. The metric keeps sizes in buckets, so the value is approximate: about 24.6 kB for a 22.7 kB backup. The exact size is in the `backup_succeeded` log line.

A failure panel shows "No data" until the first failure happens, which is the normal, healthy state.

#### Search filter

```
jsonPayload.event="http_request"
jsonPayload.method="GET"
jsonPayload.route="/search/courses/<int:course_id>/segments"
```

That route is the one that searches transcripts. Listing courses and browser `OPTIONS` requests don't count. A 4xx isn't a failure, because it's a bad request or a missing sign-in. Failures that never reach Flask, such as a load balancer 502, aren't counted either.

### Azure backup storage

Both panels read the Blob service of storage account `libackupecd087147d`, in `rg-li-backup`, one point per hour.

| Panel | Azure metric | Aggregation |
|---|---|---|
| Backups stored | `BlobCount` | Average |
| Storage used | `BlobCapacity` | Average |

`BlobCount` and `BlobCapacity` have hourly points, but Azure only refreshes them a few times a day, so they can lag a backup by several hours. We measured delays from about 1.5 hours to at least 4 hours. To see what's really there, run `make cloud-restore ARGS="list"`.

These panels show that storage changed, not that a backup can be restored. The [restore test](../runbooks/backup-and-restore.md#test-a-restore) proves that.

## Try a query yourself

- **In Grafana:** open a panel's menu and choose **Explore**, to see and change its query without affecting the dashboard.
- **In Google Cloud:** [Metrics Explorer](https://console.cloud.google.com/monitoring/metrics-explorer?project=lecture-indexer-511419) takes the same metric names, aligners and reducers.
- **For a log-based metric:** paste its filter into [Logs Explorer](https://console.cloud.google.com/logs/query?project=lecture-indexer-511419) to see the lines it counts.
- **In Azure:** `az monitor metrics list --resource <storage account ID>/blobServices/default --metric BlobCount --interval PT1H`.
