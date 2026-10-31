# Empty: the backups are in rg-li-backup, in ../../bootstrap, so that destroying
# this environment doesn't delete them (ADR 0004).
# The frontend moved to Cloud Run: docs/architecture_decision_records/0001-frontend-on-cloud-run.md.
resource "azurerm_resource_group" "this" {
  name     = "rg-${var.name}-prod"
  location = var.azure_location
  tags = merge(local.labels, {
    component = "unused"
    purpose   = "Empty; backups are in rg-li-backup"
  })
}
