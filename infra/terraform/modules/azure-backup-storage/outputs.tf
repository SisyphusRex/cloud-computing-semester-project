output "account_name" {
  value = azapi_resource.account.name
}

output "container_name" {
  value = azurerm_storage_container.this.name
}

output "container_url" {
  description = "BACKUP_CONTAINER_URL in values.env."
  value       = "https://${azapi_resource.account.name}.blob.core.windows.net/${azurerm_storage_container.this.name}"
}
