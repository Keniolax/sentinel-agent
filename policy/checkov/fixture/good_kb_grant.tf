# The real grant's shape: a read role on the knowledge container only. The policy passes it.
resource "azurerm_role_assignment" "agent_kb_ok" {
  scope                = "/subscriptions/0/resourceGroups/rg-sentinel-lab/providers/Microsoft.Storage/storageAccounts/stsentineldata/blobServices/default/containers/knowledge"
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = "00000000-0000-0000-0000-000000000000"
  principal_type       = "ServicePrincipal"
}
