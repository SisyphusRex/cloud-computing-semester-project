resource "azurerm_resource_group" "this" {
  name     = "rg-${var.name}-prod"
  location = var.azure_location
}

module "static_web_app" {
  source              = "../../modules/azure-static-web-app"
  name                = "swa-${var.name}-prod"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
}
