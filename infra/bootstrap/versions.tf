terraform {
  required_version = "~> 1.14.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "= 5.13.0"
    }
  }
  # Local state: this stack makes the storage account that holds the main stack's state. The
  # subscription owner applies it once. Every resource carries the lab tags, so a lost state
  # file can still be cleaned up by hand.
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
  # prereqs.sh registers the resource providers. Terraform registers nothing by itself.
  resource_provider_registrations = "none"
  # The state account has shared-key access turned off, so the provider must use Entra ID.
  storage_use_azuread = true
}
