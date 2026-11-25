data "azurerm_resource_group" "lab" {
  name = var.lab_resource_group
}

locals {
  suffix   = substr(sha1(var.subscription_id), 0, 6)
  location = data.azurerm_resource_group.lab.location
  rg       = data.azurerm_resource_group.lab.name
  tags     = { lab = "seceng-bootcamp-week-18", project = "sentinel-agent" }
  registry = split("/", var.agent_image)[0]
}
