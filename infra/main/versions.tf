terraform {
  required_version = "~> 1.14.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "= 5.13.0"
    }
  }
  # Partial config: the pipeline passes the resource group and storage account that the
  # bootstrap stack made. Entra ID auth only; the state account has no shared keys.
  backend "azurerm" {
    container_name   = "tfstate"
    key              = "main.tfstate"
    use_azuread_auth = true
  }
}

provider "azurerm" {
  features {}
  subscription_id                 = var.subscription_id
  resource_provider_registrations = "none"
  storage_use_azuread             = true
}
