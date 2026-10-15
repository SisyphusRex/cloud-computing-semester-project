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
  value = "https://${module.static_web_app.default_hostname}"
}

output "static_web_app" {
  value = { name = module.static_web_app.name, resource_group = azurerm_resource_group.this.name }
}

output "cloudsql" {
  value = {
    connection_name       = module.cloudsql.connection_name
    database              = module.cloudsql.database_name
    admin_username        = module.cloudsql.admin_username
    admin_password_secret = module.secrets.secret_ids["db-admin-password"]
  }
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
