output "name" {
  value = google_cloud_run_v2_service.this.name
}

output "uri" {
  description = "The service's https://<name>-<hash>.<region>.run.app URL."
  value       = google_cloud_run_v2_service.this.uri
}

# For envs/prod tests.
output "public_member" {
  value = google_cloud_run_v2_service_iam_member.public.member
}

output "public_role" {
  value = google_cloud_run_v2_service_iam_member.public.role
}

output "deployer_bindings" {
  value = { for k, b in google_cloud_run_v2_service_iam_member.deployers : k => b.member }
}
