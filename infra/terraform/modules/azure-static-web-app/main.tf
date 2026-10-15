# Free-tier Static Web App for the React SPA. Deploys use a token that CI
# fetches at deploy time with its federated identity, so none is stored in GitHub.

resource "azurerm_static_web_app" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  sku_tier            = "Free"
  sku_size            = "Free"
}
