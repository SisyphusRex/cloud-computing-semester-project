# Azure holds the nightly database backups (step 5: modules/azure-backup-storage).
# The frontend moved to Cloud Run: docs/architecture_decision_records/0001-frontend-on-cloud-run.md.
resource "azurerm_resource_group" "this" {
  name     = "rg-${var.name}-prod"
  location = var.azure_location
}
