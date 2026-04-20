terraform {
  backend "azurerm" {
    resource_group_name  = "rg-gradescale-tfstate"
    storage_account_name = "stgradescaletfstate15042"
    container_name       = "tfstate"
    key                  = "dev.terraform.tfstate"
  }
}
