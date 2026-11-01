# Read-only identities for Grafana Cloud (docs/monitoring/grafana-cloud-plan.md).
# Grafana Cloud runs outside both clouds, so unlike CI it can't sign in without a
# credential. Terraform owns only the identities and their roles: the Google key
# and Azure client secret must never land in state, so a script creates them.

resource "google_service_account" "grafana" {
  account_id   = "li-grafana"
  display_name = "Grafana Cloud (read-only metrics)"
}

# Metrics only: raw logs would need roles/logging.viewer as well.
resource "google_project_iam_member" "grafana" {
  project = var.gcp_project_id
  role    = "roles/monitoring.viewer"
  member  = google_service_account.grafana.member
}

data "azuread_client_config" "current" {}

# Whoever applies bootstrap must own these: without being an owner, a user with
# no Entra role can't create the service principal or a client secret.
resource "azuread_application" "grafana" {
  display_name = "li-grafana"
  owners       = [data.azuread_client_config.current.object_id]
}

resource "azuread_service_principal" "grafana" {
  client_id = azuread_application.grafana.client_id
  owners    = [data.azuread_client_config.current.object_id]
}

# The backups are all Azure has to chart. Monitoring Reader can't read blobs.
resource "azurerm_role_assignment" "grafana" {
  scope                = azurerm_resource_group.backup.id
  role_definition_name = "Monitoring Reader"
  principal_id         = azuread_service_principal.grafana.object_id
  principal_type       = "ServicePrincipal"
}
