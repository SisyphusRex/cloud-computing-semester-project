output "backup_alert_ids" {
  value = google_monitoring_alert_policy.backup_failed[*].id
}

output "log_metric_names" {
  description = "Charted under logging.googleapis.com/user/<name>."
  value = concat(
    [for m in google_logging_metric.event : m.name],
    [google_logging_metric.app_errors.name, google_logging_metric.backup_bytes.name],
  )
}
