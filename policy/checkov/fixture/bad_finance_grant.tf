# A fixture the custom policy must reject: a Storage Blob Data role on the finance container,
# the exact misconfiguration the capstone's second lock forbids. Not part of infra/, never
# applied; the gate scans it only to prove the policy fails on it. The scope is written in
# full so the HCL parser resolves it without the rest of the stack.
resource "azurerm_role_assignment" "agent_finance_bad" {
  scope                = "/subscriptions/0/resourceGroups/rg-sentinel-lab/providers/Microsoft.Storage/storageAccounts/stsentineldata/blobServices/default/containers/finance"
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = "00000000-0000-0000-0000-000000000000"
  principal_type       = "ServicePrincipal"
}
