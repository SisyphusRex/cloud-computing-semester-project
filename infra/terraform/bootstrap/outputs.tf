output "github_variables" {
  description = "Set these as GitHub Actions repository variables (none are secrets)."
  value = {
    GCP_PROJECT_ID                 = var.gcp_project_id
    GCP_REGION                     = var.gcp_region
    GCP_WORKLOAD_IDENTITY_PROVIDER = google_iam_workload_identity_pool_provider.github.name
    GCP_TERRAFORM_SA               = google_service_account.terraform.email
    GCP_DEPLOY_SA                  = google_service_account.deploy.email
    GCP_PLAN_SA                    = google_service_account.plan.email
    TF_STATE_BUCKET                = var.state_bucket
    AZURE_CLIENT_ID                = azurerm_user_assigned_identity.github.client_id
    AZURE_PLAN_CLIENT_ID           = azurerm_user_assigned_identity.plan.client_id
    AZURE_TENANT_ID                = azurerm_user_assigned_identity.github.tenant_id
    AZURE_SUBSCRIPTION_ID          = var.azure_subscription_id
  }
}

output "deploy_service_account" {
  description = "Passed to envs/prod so it can grant the deploy SA push access to Artifact Registry."
  value       = google_service_account.deploy.email
}

output "backup_container_url" {
  description = "BACKUP_CONTAINER_URL in deploy/k8s/overlays/prod/values/values.env."
  value       = module.backup_storage.container_url
}
