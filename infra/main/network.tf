# One virtual network, two subnets, no NAT gateway (about $32 a month). Nothing accepts
# inbound traffic. The job's subnet may reach only the Azure services Microsoft lists for a
# workload-profiles environment, plus storage in this region; everything else on the
# internet is denied.

resource "azurerm_virtual_network" "lab" {
  name                = "vnet-sentinel"
  resource_group_name = local.rg
  location            = local.location
  address_space       = ["10.40.0.0/16"]
  tags                = local.tags
}

resource "azurerm_subnet" "jobs" {
  name                 = "snet-jobs"
  resource_group_name  = local.rg
  virtual_network_name = azurerm_virtual_network.lab.name
  address_prefixes     = ["10.40.0.0/27"]
  # The Container Apps platform sends the job's outbound traffic itself; the NSG below
  # limits where it may go.
  default_outbound_access_enabled = true
  delegation {
    name = "container-apps"
    service_delegation {
      name    = "Microsoft.App/environments"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

resource "azurerm_subnet" "siem" {
  name                 = "snet-siem"
  resource_group_name  = local.rg
  virtual_network_name = azurerm_virtual_network.lab.name
  address_prefixes     = ["10.40.1.0/24"]
  # The SIEM's only way out is its own public IP, which the NSG limits to HTTP and HTTPS.
  default_outbound_access_enabled = false
}

locals {
  # From "Securing a virtual network: workload profiles environment", Microsoft Learn.
  job_egress = {
    mcr          = { priority = 100, tag = "MicrosoftContainerRegistry", why = "Platform system containers" }
    frontdoor    = { priority = 110, tag = "AzureFrontDoor.FirstParty", why = "Dependency of MicrosoftContainerRegistry" }
    entra        = { priority = 120, tag = "AzureActiveDirectory", why = "Managed identity tokens" }
    monitor      = { priority = 130, tag = "AzureMonitor", why = "Console logs to Log Analytics" }
    registry     = { priority = 140, tag = "AzureContainerRegistry", why = "Pull the agent image from the lab registry" }
    region_store = { priority = 150, tag = "Storage.${local.location}", why = "Registry layers and the knowledge-base container" }
  }
}

resource "azurerm_network_security_group" "jobs" {
  name                = "nsg-sentinel-jobs"
  resource_group_name = local.rg
  location            = local.location
  tags                = local.tags
}

resource "azurerm_network_security_rule" "jobs_egress" {
  for_each                    = local.job_egress
  name                        = "allow-${each.key}"
  description                 = each.value.why
  network_security_group_name = azurerm_network_security_group.jobs.name
  resource_group_name         = local.rg
  priority                    = each.value.priority
  direction                   = "Outbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_address_prefix       = "*"
  source_port_range           = "*"
  destination_address_prefix  = each.value.tag
  destination_port_range      = "443"
}

resource "azurerm_network_security_rule" "jobs_intra" {
  name                        = "allow-subnet"
  description                 = "Traffic between addresses in the job subnet"
  network_security_group_name = azurerm_network_security_group.jobs.name
  resource_group_name         = local.rg
  priority                    = 200
  direction                   = "Outbound"
  access                      = "Allow"
  protocol                    = "*"
  source_address_prefix       = "*"
  source_port_range           = "*"
  destination_address_prefix  = azurerm_subnet.jobs.address_prefixes[0]
  destination_port_range      = "*"
}

resource "azurerm_network_security_rule" "jobs_deny_internet" {
  name                        = "deny-internet"
  description                 = "Everything not allowed above, including the SIEM subnet"
  network_security_group_name = azurerm_network_security_group.jobs.name
  resource_group_name         = local.rg
  priority                    = 4000
  direction                   = "Outbound"
  access                      = "Deny"
  protocol                    = "*"
  source_address_prefix       = "*"
  source_port_range           = "*"
  destination_address_prefix  = "*"
  destination_port_range      = "*"
}

resource "azurerm_network_security_group" "siem" {
  name                = "nsg-sentinel-siem"
  resource_group_name = local.rg
  location            = local.location
  tags                = local.tags
}

resource "azurerm_network_security_rule" "siem_deny_inbound" {
  name                        = "deny-all-inbound"
  description                 = "No inbound traffic at all, from the internet or the job subnet; operators use Run Command"
  network_security_group_name = azurerm_network_security_group.siem.name
  resource_group_name         = local.rg
  priority                    = 4000
  direction                   = "Inbound"
  access                      = "Deny"
  protocol                    = "*"
  source_address_prefix       = "*"
  source_port_range           = "*"
  destination_address_prefix  = "*"
  destination_port_range      = "*"
}

# trivy:ignore:AZU-0051 HTTPS and HTTP out only, to Azure APIs, GitHub, the image registry and the Ubuntu mirror; no NAT gateway in this lab
resource "azurerm_network_security_rule" "siem_egress" {
  for_each                    = { https = { priority = 100, port = "443" }, http = { priority = 110, port = "80" } }
  name                        = "allow-${each.key}-out"
  description                 = "Package, image and Azure API downloads"
  network_security_group_name = azurerm_network_security_group.siem.name
  resource_group_name         = local.rg
  priority                    = each.value.priority
  direction                   = "Outbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_address_prefix       = "*"
  source_port_range           = "*"
  destination_address_prefix  = "Internet"
  destination_port_range      = each.value.port
}

resource "azurerm_network_security_rule" "siem_deny_out" {
  name                        = "deny-other-out"
  description                 = "Everything not allowed above"
  network_security_group_name = azurerm_network_security_group.siem.name
  resource_group_name         = local.rg
  priority                    = 4000
  direction                   = "Outbound"
  access                      = "Deny"
  protocol                    = "*"
  source_address_prefix       = "*"
  source_port_range           = "*"
  destination_address_prefix  = "Internet"
  destination_port_range      = "*"
}

resource "azurerm_subnet_network_security_group_association" "jobs" {
  subnet_id                 = azurerm_subnet.jobs.id
  network_security_group_id = azurerm_network_security_group.jobs.id
}

resource "azurerm_subnet_network_security_group_association" "siem" {
  subnet_id                 = azurerm_subnet.siem.id
  network_security_group_id = azurerm_network_security_group.siem.id
}

# Container Apps does not support VNet flow logs, so they cover the SIEM subnet only.
resource "azurerm_network_watcher_flow_log" "siem" {
  name                 = "fl-sentinel-siem"
  network_watcher_name = var.network_watcher_name
  resource_group_name  = local.rg
  location             = local.location
  target_resource_id   = azurerm_subnet.siem.id
  storage_account_id   = azurerm_storage_account.flow.id
  enabled              = true
  version              = 2
  retention_policy {
    enabled = true
    days    = 90
  }
  tags = local.tags
}
