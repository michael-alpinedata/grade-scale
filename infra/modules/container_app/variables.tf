variable "app_name" { type = string }
variable "env_id" { type = string }
variable "rg_name" { type = string }
variable "image_name" { type = string }
variable "cpu" {
  type    = number
  default = 0.25
}
variable "memory" {
  type    = string
  default = "0.5Gi"
}
variable "database_url_secret_id" {
  type      = string
}
variable "groq_api_key_secret_id" {
  description = "The ID of the Key Vault secret for the Groq API key"
  type        = string
}

variable "identity_id" {
  description = "The ID of the user assigned identity"
  type        = string
}
variable "github_username" {
  type      = string
}
variable "github_pat_secret_id" {
  type      = string
}

variable "groq_base_url" {
  type    = string
  default = "https://api.groq.com/openai/v1"
}
