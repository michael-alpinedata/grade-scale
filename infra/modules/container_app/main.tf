resource "azurerm_container_app" "main" {
  name                         = var.app_name
  container_app_environment_id = var.env_id
  resource_group_name          = var.rg_name
  revision_mode                = "Single"

  identity {
    type         = "UserAssigned"
    identity_ids = [var.identity_id]
  }

  template {
    container {
      name   = "gradescale-api"
      image  = var.image_name
      cpu    = var.cpu
      memory = var.memory

      env {
        name  = "DATABASE_URL"
        secret_name = "database-url"
      }
      env {
        name  = "GROQ_API_KEY"
        secret_name = "groq-api-key"
      }
      env {
        name  = "GROQ_BASE_URL"
        value = var.groq_base_url
      }
      env {
        name  = "PORT"
        value = "3000"
      }
    }
  }

  secret {
    name                = "database-url"
    key_vault_secret_id = var.database_url_secret_id
    identity            = var.identity_id
  }

  secret {
    name                = "groq-api-key"
    key_vault_secret_id = var.groq_api_key_secret_id
    identity            = var.identity_id
  }

  secret {
    name                = "github-pat"
    key_vault_secret_id = var.github_pat_secret_id
    identity            = var.identity_id
  }

  registry {
    server               = "ghcr.io"
    username             = var.github_username
    password_secret_name = "github-pat"
  }

  ingress {
    external_enabled = true
    target_port      = 3000
    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }
}
