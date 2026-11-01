# The backup alert, and the log-based metrics that the Grafana dashboard charts
# (docs/monitoring/grafana-cloud-plan.md). The other alerts come later
# (docs/implementation-plan.md, step 5).

locals {
  # Every line the app and backup.sh log carries an `event` (li_common.logs).
  event_counters = toset([
    "backup_succeeded",
    "backup_failed",
    "ingest_succeeded",
    "ingest_failed",
  ])
}

resource "google_logging_metric" "event" {
  for_each = local.event_counters
  name     = each.value
  filter   = "jsonPayload.event=\"${each.value}\""

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
  }
}

resource "google_logging_metric" "app_errors" {
  name   = "app_errors"
  filter = <<-EOT
    resource.type="k8s_container"
    resource.labels.namespace_name="${var.namespace}"
    severity>=ERROR
  EOT

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
  }
}

# Size of each backup, as uploaded to Azure.
resource "google_logging_metric" "backup_bytes" {
  name            = "backup_bytes"
  filter          = "jsonPayload.event=\"backup_succeeded\""
  value_extractor = "EXTRACT(jsonPayload.bytes)"

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "DISTRIBUTION"
    unit        = "By"
  }

  # 1 KiB to about 1 GiB, the most the job's 1 Gi emptyDir can hold.
  bucket_options {
    exponential_buckets {
      num_finite_buckets = 20
      growth_factor      = 2
      scale              = 1024
    }
  }
}

# Kubernetes records these events when a Job gives up, whatever made it fail.
resource "google_monitoring_alert_policy" "backup_failed" {
  count        = var.notification_channel == "" ? 0 : 1
  display_name = "Database backup failed"
  combiner     = "OR"
  user_labels  = var.labels

  conditions {
    display_name = "A backup Job gave up"
    condition_matched_log {
      filter = <<-EOT
        log_id("events")
        jsonPayload.involvedObject.kind="Job"
        jsonPayload.involvedObject.name:"backup"
        jsonPayload.reason=("BackoffLimitExceeded" OR "DeadlineExceeded")
      EOT
    }
  }

  # Log-match conditions must set a rate limit.
  alert_strategy {
    auto_close = "86400s"
    notification_rate_limit {
      period = "3600s"
    }
  }

  notification_channels = [var.notification_channel]

  documentation {
    mime_type = "text/markdown"
    content   = "A database backup failed. See docs/runbooks/backup-and-restore.md."
  }
}
