output "secret_ids" {
  description = "Secret ID => full resource name (projects/<n>/secrets/<id>)."
  value       = { for k, s in google_secret_manager_secret.this : k => s.id }
}

output "values_in_state" {
  description = "Secrets whose value is stored in state; always empty because values are write-only. Asserted by envs/prod tests."
  value       = { for k, v in google_secret_manager_secret_version.this : k => v.secret_data if v.secret_data != null }
  sensitive   = true
}
