output "resource_group_name" {
  value = azurerm_resource_group.dev.name
}

output "container_app_url" {
  value = module.api.url
}

output "static_web_app_url" {
  value = module.frontend.default_host_name
}

output "frontend_deployment_token" {
  value     = module.frontend.api_key
  sensitive = true
}

output "key_vault_name" {
  value = module.security.name
}

output "database_host" {
  value = module.database.server_fqdn
}
