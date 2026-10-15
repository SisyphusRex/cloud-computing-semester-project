output "name" {
  value = azurerm_static_web_app.this.name
}

output "default_hostname" {
  value = azurerm_static_web_app.this.default_host_name
}
