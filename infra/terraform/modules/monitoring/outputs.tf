output "backup_alert_ids" {
  value = google_monitoring_alert_policy.backup_failed[*].id
}
