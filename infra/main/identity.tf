# Two managed identities, one per workload. The deploy identity may grant only AcrPull,
# Storage Blob Data Reader and Log Analytics Reader, and only to service principals (see the
# bootstrap stack), so principal_type must be set on every assignment here.

resource "azurerm_user_assigned_identity" "agent" {
  name                = "id-sentinel-agent"
  resource_group_name = local.rg
  location            = local.location
  tags                = local.tags
}

# Pull the image, and read the knowledge-base container. Nothing in "finance".
resource "azurerm_role_assignment" "agent_pull" {
  scope                = var.acr_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.agent.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "agent_kb" {
  scope                = azurerm_storage_container.c["kb"].id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = azurerm_user_assigned_identity.agent.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_user_assigned_identity" "siem" {
  name                = "id-sentinel-siem"
  resource_group_name = local.rg
  location            = local.location
  tags                = local.tags
}

# The SIEM's collector queries the workspace. It holds no other role.
resource "azurerm_role_assignment" "siem_logs" {
  scope                = azurerm_log_analytics_workspace.lab.id
  role_definition_name = "Log Analytics Reader"
  principal_id         = azurerm_user_assigned_identity.siem.principal_id
  principal_type       = "ServicePrincipal"
}
