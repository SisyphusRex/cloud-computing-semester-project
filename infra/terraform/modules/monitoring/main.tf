# Only the backup alert so far; the dashboard and the other alerts come later
# (docs/implementation-plan.md, step 5).

# Kubernetes records these events when a Job gives up, whatever made it fail.
resource "google_monitoring_alert_policy" "backup_failed" {
  count        = var.notification_channel == "" ? 0 : 1
  display_name = "Database backup failed"
  combiner     = "OR"

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
