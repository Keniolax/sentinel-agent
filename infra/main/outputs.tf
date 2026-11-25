output "resource_group" { value = local.rg }
output "job_name" { value = azurerm_container_app_job.agent.name }
output "workspace_id" { value = azurerm_log_analytics_workspace.lab.workspace_id }
output "data_account" { value = azurerm_storage_account.data.name }
output "siem_vm_name" { value = azurerm_linux_virtual_machine.siem.name }
output "agent_principal_id" { value = azurerm_user_assigned_identity.agent.principal_id }
