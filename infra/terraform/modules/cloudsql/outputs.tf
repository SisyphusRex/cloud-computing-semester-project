output "connection_name" {
  description = "project:region:instance, as passed to the Cloud SQL Auth Proxy."
  value       = google_sql_database_instance.this.connection_name
}

output "database_name" {
  value = google_sql_database.app.name
}

output "admin_username" {
  value = google_sql_user.admin.name
}

output "iam_usernames" {
  description = "Database user name for each IAM service account, keyed like the input."
  value       = { for k, u in google_sql_user.iam : k => u.name }
}

output "admin_password_in_state" {
  description = "Always null: the password is write-only. Asserted by envs/prod tests."
  value       = google_sql_user.admin.password
  sensitive   = true
}
