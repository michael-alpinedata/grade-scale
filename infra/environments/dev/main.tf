resource "azurerm_resource_group" "dev" {
  name     = "rg-gradescale-dev"
  location = "France Central"
}

data "azurerm_client_config" "current" {}
 
provider "github" {
  token = var.github_pat
  owner = var.github_username
}

module "security" {
  source              = "../../modules/key_vault"
  name                = "kv-gradescale-dev-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.dev.name
  location            = azurerm_resource_group.dev.location
  tenant_id           = data.azurerm_client_config.current.tenant_id
  admin_object_id     = data.azurerm_client_config.current.object_id
}

resource "azurerm_user_assigned_identity" "api" {
  name                = "id-gradescale-api-dev"
  resource_group_name = azurerm_resource_group.dev.name
  location            = azurerm_resource_group.dev.location
}

resource "azurerm_key_vault_access_policy" "admin" {
  key_vault_id = module.security.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id

  secret_permissions = ["Get", "List", "Set", "Delete", "Purge", "Recover"]
}

resource "azurerm_key_vault_access_policy" "api" {
  key_vault_id = module.security.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_user_assigned_identity.api.principal_id

  secret_permissions = ["Get", "List"]
}

resource "azurerm_key_vault_secret" "database_url" {
  name         = "database-url"
  value        = "postgresql://${module.database.admin_username}:${var.db_password}@${module.database.server_fqdn}:5432/${module.database.db_name}?sslmode=require"
  key_vault_id = module.security.id
  
  # Ensure the secret is created after the DB is ready
  depends_on = [module.database]
}

resource "azurerm_key_vault_secret" "groq_api_key" {
  name         = "groq-api-key"
  value        = var.groq_api_key
  key_vault_id = module.security.id
}

resource "azurerm_key_vault_secret" "github_pat" {
  name         = "github-pat"
  value        = var.github_pat
  key_vault_id = module.security.id
}



module "database" {
  source              = "../../modules/postgres"
  resource_group_name = azurerm_resource_group.dev.name
  location            = azurerm_resource_group.dev.location
  server_name         = "pg-gradescale-dev-${random_string.suffix.result}"
  admin_username      = "psqladmin"
  admin_password      = var.db_password
  db_name             = "gradescale_dev"
}

module "environment" {
  source              = "../../modules/aca_env"
  resource_group_name = azurerm_resource_group.dev.name
  location            = azurerm_resource_group.dev.location
  env_name            = "cae-gradescale-dev"
}

module "api" {
  source                 = "../../modules/container_app"
  rg_name                = azurerm_resource_group.dev.name
  env_id                 = module.environment.id
  app_name               = "aca-gradescale-api-dev"
  image_name             = "ghcr.io/${var.github_username}/grade-scale:latest"
  cpu                    = 0.25
  memory                 = "0.5Gi"
  github_username        = var.github_username
  github_pat_secret_id   = azurerm_key_vault_secret.github_pat.versionless_id
  database_url_secret_id = azurerm_key_vault_secret.database_url.versionless_id
  groq_api_key_secret_id = azurerm_key_vault_secret.groq_api_key.versionless_id
  identity_id            = azurerm_user_assigned_identity.api.id
}

module "frontend" {
  source              = "../../modules/static_web_app"
  name                = "stapp-gradescale-dev"
  resource_group_name = azurerm_resource_group.dev.name
  location            = "West Europe"
}

resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}
 
resource "github_actions_secret" "swa_token" {
  repository      = "grade-scale"
  secret_name     = "AZURE_SWA_TOKEN"
  plaintext_value = module.frontend.api_key
}



