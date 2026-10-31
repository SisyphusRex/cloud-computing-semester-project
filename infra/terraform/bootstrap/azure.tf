# Keyless GitHub Actions -> Azure: user-assigned managed identities trust
# GitHub's OIDC tokens for one exact subject each. No app registration or secret.
#   id-li-github       Contributor, jobs in the protected GitHub environment
#   id-li-github-plan  Reader, pull request jobs and the release plan job (prod-plan)

data "azurerm_subscription" "current" {}

resource "azurerm_resource_group" "ci" {
  name     = "rg-li-ci"
  location = var.azure_location
}

resource "azurerm_user_assigned_identity" "github" {
  name                = "id-li-github"
  resource_group_name = azurerm_resource_group.ci.name
  location            = azurerm_resource_group.ci.location
}

resource "azurerm_federated_identity_credential" "github" {
  name                      = "github-environment-${var.github_environment}"
  user_assigned_identity_id = azurerm_user_assigned_identity.github.id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = "https://token.actions.githubusercontent.com"
  subject                   = "${var.github_subject_prefix}:environment:${var.github_environment}"
}

resource "azurerm_role_assignment" "github_contributor" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_user_assigned_identity.github.principal_id
}

resource "azurerm_user_assigned_identity" "plan" {
  name                = "id-li-github-plan"
  resource_group_name = azurerm_resource_group.ci.name
  location            = azurerm_resource_group.ci.location
}

resource "azurerm_federated_identity_credential" "plan" {
  name                      = "github-pull-request"
  user_assigned_identity_id = azurerm_user_assigned_identity.plan.id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = "https://token.actions.githubusercontent.com"
  subject                   = "${var.github_subject_prefix}:pull_request"
}

# The release workflow's plan job, before anyone approves the release.
resource "azurerm_federated_identity_credential" "plan_environment" {
  name                      = "github-environment-${var.github_plan_environment}"
  user_assigned_identity_id = azurerm_user_assigned_identity.plan.id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = "https://token.actions.githubusercontent.com"
  subject                   = "${var.github_subject_prefix}:environment:${var.github_plan_environment}"
}

# Read-only: enough for release.yml's full-refresh plan. PR plans skip the
# refresh (-refresh=false) and only need it to read state.
resource "azurerm_role_assignment" "plan_reader" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Reader"
  principal_id         = azurerm_user_assigned_identity.plan.principal_id
}

# Database backups live here, not in envs/prod: `terraform destroy` there deletes
# the database, and must leave its backups behind (ADR 0004).
resource "azurerm_resource_group" "backup" {
  name     = "rg-li-backup"
  location = var.azure_location
}

module "backup_storage" {
  source            = "../modules/azure-backup-storage"
  account_name      = "libackup${substr(sha1(var.azure_subscription_id), 0, 10)}"
  resource_group_id = azurerm_resource_group.backup.id
  location          = azurerm_resource_group.backup.location
}
