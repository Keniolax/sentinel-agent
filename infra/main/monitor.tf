# One Log Analytics workspace collects the three log sources the SIEM reads:
#   ContainerAppConsoleLogs  the agent's own JSON lines (CloudWatch Logs in the AWS version)
#   StorageBlobLogs          every read and write on the data account (CloudTrail data events)
#   AzureActivity            control-plane changes in the subscription (CloudTrail management)

resource "azurerm_log_analytics_workspace" "lab" {
  name                = "log-sentinel"
  resource_group_name = local.rg
  location            = local.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
  # A cap so a runaway log loop cannot spend the trial credit. The lab writes a few MB a day.
  daily_quota_gb = 1
  # Every writer uses a diagnostic setting and every reader an Entra ID token; no shared key.
  local_authentication_enabled = false
  tags                         = local.tags
}

resource "azurerm_monitor_diagnostic_setting" "blob" {
  name                       = "sentinel-blob-access"
  target_resource_id         = "${azurerm_storage_account.data.id}/blobServices/default"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.lab.id
  enabled_log { category = "StorageRead" }
  enabled_log { category = "StorageWrite" }
  enabled_log { category = "StorageDelete" }
}

resource "azurerm_monitor_diagnostic_setting" "activity" {
  name                       = "sentinel-activity"
  target_resource_id         = "/subscriptions/${var.subscription_id}"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.lab.id
  enabled_log { category = "Administrative" }
  enabled_log { category = "Security" }
  enabled_log { category = "Policy" }
}

resource "azurerm_monitor_diagnostic_setting" "jobs" {
  name                           = "sentinel-job-logs"
  target_resource_id             = azurerm_container_app_environment.lab.id
  log_analytics_workspace_id     = azurerm_log_analytics_workspace.lab.id
  log_analytics_destination_type = "Dedicated"
  enabled_log { category = "ContainerAppConsoleLogs" }
  enabled_log { category = "ContainerAppSystemLogs" }
}
