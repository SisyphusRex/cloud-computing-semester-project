# Where the nightly encrypted pg_dump goes (ADR 0004). Blobs can't be changed or
# deleted for immutable_days, even with the account key, and are cleaned up
# after delete_after_days. The policy is unlocked so the project can still be
# torn down: a subscription owner can remove it.

# azapi, not azurerm_storage_account: that resource always copies the account
# keys into Terraform state. This one stores only the settings below.
resource "azapi_resource" "account" {
  type      = "Microsoft.Storage/storageAccounts@2023-05-01"
  name      = var.account_name
  parent_id = var.resource_group_id
  location  = var.location

  body = {
    kind = "StorageV2"
    sku  = { name = "Standard_LRS" }
    properties = {
      accessTier               = "Cool"
      supportsHttpsTrafficOnly = true
      minimumTlsVersion        = "TLS1_2"
      allowBlobPublicAccess    = false
      # scripts/cloud-backup-sas.sh signs the upload SAS with the account key.
      allowSharedKeyAccess = true
    }
  }
}

resource "azurerm_storage_container" "this" {
  name                  = var.container_name
  storage_account_id    = azapi_resource.account.id
  container_access_type = "private"
}

resource "azurerm_storage_container_immutability_policy" "this" {
  storage_container_resource_manager_id = azurerm_storage_container.this.id
  immutability_period_in_days           = var.immutable_days
  locked                                = false
}

resource "azurerm_storage_management_policy" "this" {
  storage_account_id = azapi_resource.account.id

  rule {
    name    = "delete-old-backups"
    enabled = true

    filters {
      blob_types   = ["blockBlob"]
      prefix_match = ["${var.container_name}/"]
    }

    actions {
      base_blob {
        delete_after_days_since_creation_greater_than = var.delete_after_days
      }
    }
  }
}
