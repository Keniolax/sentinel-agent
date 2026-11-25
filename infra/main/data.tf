# The data account holds two containers. The agent's identity can read "knowledge" and nothing else;
# "finance" holds the synthetic payroll file an attacker would want.

# trivy:ignore:AZU-0012 The job reaches storage over its public endpoint (a private endpoint costs about $7 a month); shared keys are off and every request needs an Entra ID token
# trivy:ignore:AZU-0057 Classic Storage Analytics logging; azurerm_monitor_diagnostic_setting.blob sends every blob read, write and delete to Log Analytics instead
# trivy:ignore:AZU-0058 One-region lab; blob versioning covers a bad write, and geo-replication would double the cost
# trivy:ignore:AZU-0060 Microsoft-managed keys plus infrastructure encryption; a customer key needs a Key Vault with purge protection, which outlives the lab by at least 7 days
resource "azurerm_storage_account" "data" {
  # checkov:skip=CKV_AZURE_206:One-region lab; blob versioning covers a bad write, and geo-replication would double the cost
  # checkov:skip=CKV2_AZURE_33:A private endpoint costs about $7 a month; shared keys are off and every request needs an Entra ID token
  # checkov:skip=CKV_AZURE_59:GitHub-hosted runners upload the seed data and have no fixed address; shared keys are off and every request needs an Entra ID token
  # checkov:skip=CKV2_AZURE_1:Microsoft-managed keys plus infrastructure encryption; a customer key needs a Key Vault with purge protection, which outlives the lab by at least 7 days
  # checkov:skip=CKV_AZURE_33:The account has no queues
  name                              = "stsentineldata${local.suffix}"
  resource_group_name               = local.rg
  location                          = local.location
  account_tier                      = "Standard"
  account_replication_type          = "LRS"
  min_tls_version                   = "TLS1_2"
  https_traffic_only_enabled        = true
  shared_access_key_enabled         = false
  default_to_oauth_authentication   = true
  allow_nested_items_to_be_public   = false
  local_user_enabled                = false
  infrastructure_encryption_enabled = true
  cross_tenant_replication_enabled  = false
  public_network_access             = "Enabled"

  blob_properties {
    versioning_enabled = true
    delete_retention_policy { days = 7 }
    container_delete_retention_policy { days = 7 }
  }
  sas_policy {
    expiration_period = "00.01:00:00"
  }
  tags = local.tags
}

resource "azurerm_storage_container" "c" {
  # checkov:skip=CKV2_AZURE_21:azurerm_monitor_diagnostic_setting.blob sends every read, write and delete on the account to Log Analytics; Checkov does not follow that link
  # Container names need at least three characters; the map keys stay short.
  for_each              = { kb = "knowledge", finance = "finance" }
  name                  = each.value
  storage_account_id    = azurerm_storage_account.data.id
  container_access_type = "private"
}

# Blob names keep the kb/ prefix, so the agent's key check is the same as in the AWS version
# (tag aws-v1).
resource "azurerm_storage_blob" "kb" {
  for_each             = fileset("${path.module}/../../kb", "*.md")
  name                 = "kb/${each.value}"
  storage_container_id = azurerm_storage_container.c["kb"].id
  type                 = "Block"
  source               = "${path.module}/../../kb/${each.value}"
  content_md5          = filemd5("${path.module}/../../kb/${each.value}")
  content_type         = "text/markdown"
}

resource "azurerm_storage_blob" "finance" {
  for_each             = fileset("${path.module}/../../finance", "*")
  name                 = "records/${each.value}"
  storage_container_id = azurerm_storage_container.c["finance"].id
  type                 = "Block"
  source               = "${path.module}/../../finance/${each.value}"
  content_md5          = filemd5("${path.module}/../../finance/${each.value}")
}

# VNet flow logs land here. Network Watcher tries a key first and then an Entra ID token, so
# the account works with shared keys off.
# trivy:ignore:AZU-0012 Only Network Watcher writes here, as a trusted Azure service; shared keys are off and every request needs an Entra ID token
# trivy:ignore:AZU-0057 Classic Storage Analytics logging; only Network Watcher writes to this account
# trivy:ignore:AZU-0058 One-region lab; flow logs are kept 90 days and are not worth a second copy
resource "azurerm_storage_account" "flow" {
  # checkov:skip=CKV_AZURE_206:One-region lab; flow logs are kept 90 days and are not worth a second copy
  # checkov:skip=CKV2_AZURE_33:A private endpoint costs about $7 a month; shared keys are off and every request needs an Entra ID token
  # checkov:skip=CKV_AZURE_59:Only Network Watcher writes here; shared keys are off and every request needs an Entra ID token
  # checkov:skip=CKV2_AZURE_1:Microsoft-managed keys plus infrastructure encryption; Network Watcher stops writing when a customer key rotates
  # checkov:skip=CKV_AZURE_33:The account has no queues
  # checkov:skip=CKV2_AZURE_38:Flow-log blobs are written once and expire after 90 days; soft delete would only delay that
  name                              = "stsentinelflow${local.suffix}"
  resource_group_name               = local.rg
  location                          = local.location
  account_tier                      = "Standard"
  account_replication_type          = "LRS"
  min_tls_version                   = "TLS1_2"
  https_traffic_only_enabled        = true
  shared_access_key_enabled         = false
  default_to_oauth_authentication   = true
  allow_nested_items_to_be_public   = false
  local_user_enabled                = false
  infrastructure_encryption_enabled = true
  cross_tenant_replication_enabled  = false
  public_network_access             = "Enabled"
  sas_policy {
    expiration_period = "00.01:00:00"
  }
  tags = local.tags
}
