# Everything deploy/k8s and the workflows need (step 4).

output "gke_cluster" {
  value = { name = module.gke.name, location = module.gke.location }
}

output "image_repository" {
  value = module.artifact_registry.repository_url
}

output "api_ip" {
  value = google_compute_global_address.api.address
}

output "api_hostname" {
  value = local.api_hostname
}

output "frontend_url" {
  description = "The Cloud Run URL: CORS_ORIGINS in values.env, and an OAuth JavaScript origin."
  value       = module.frontend.uri
}

output "frontend_service" {
  value = { name = module.frontend.name, region = var.gcp_region }
}

output "cloudsql" {
  value = {
    connection_name       = module.cloudsql.connection_name
    database              = module.cloudsql.database_name
    admin_username        = module.cloudsql.admin_username
    admin_password_secret = module.secrets.secret_ids["db-admin-password"]
  }
}

output "backup_sas_secret" {
  value = google_secret_manager_secret.backup_sas.id
}

output "workload_service_accounts" {
  description = "Annotate each Kubernetes service account with iam.gke.io/gcp-service-account."
  value       = { for k, sa in google_service_account.workload : k => sa.email }
}

output "migrate_grants" {
  description = "Value for LI_MIGRATE_GRANTS in the migrate Job."
  value = join(",", [
    "li_ingest_role=${module.cloudsql.iam_usernames["ingest"]}",
    "li_search_role=${module.cloudsql.iam_usernames["search"]}",
  ])
}
