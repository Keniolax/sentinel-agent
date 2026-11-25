# Each output becomes a GitHub repository variable of the same name in upper case
# (scripts/set-repo-vars.sh). None is a secret.
output "azure_client_id" { value = azurerm_user_assigned_identity.deploy.client_id }
output "azure_tenant_id" { value = data.azurerm_client_config.me.tenant_id }
output "azure_subscription_id" { value = var.subscription_id }
output "state_resource_group" { value = azurerm_resource_group.bootstrap.name }
output "state_storage_account" { value = azurerm_storage_account.state.name }
output "lab_resource_group" { value = azurerm_resource_group.lab.name }
output "acr_name" { value = azurerm_container_registry.agent.name }
output "acr_login_server" { value = azurerm_container_registry.agent.login_server }
output "acr_id" { value = azurerm_container_registry.agent.id }
output "network_watcher_name" { value = azurerm_network_watcher.lab.name }
