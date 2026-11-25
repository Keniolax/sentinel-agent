# One job execution answers one question and stops. Nothing runs between questions.

resource "azurerm_container_app_environment" "lab" {
  name                     = "cae-sentinel"
  resource_group_name      = local.rg
  location                 = local.location
  infrastructure_subnet_id = azurerm_subnet.jobs.id
  # No ingress is used; an internal load balancer keeps the environment off the internet.
  internal_load_balancer_enabled = true
  # Logs go through the diagnostic setting in monitor.tf, signed by the platform, so the
  # workspace needs no shared key.
  logs_destination = "azure-monitor"
  workload_profile {
    name                  = "Consumption"
    workload_profile_type = "Consumption"
  }
  tags = local.tags
}

resource "azurerm_container_app_job" "agent" {
  name                         = "caj-sentinel-agent"
  resource_group_name          = local.rg
  location                     = local.location
  container_app_environment_id = azurerm_container_app_environment.lab.id
  workload_profile_name        = "Consumption"
  replica_timeout_in_seconds   = 900
  replica_retry_limit          = 0

  manual_trigger_config {
    parallelism              = 1
    replica_completion_count = 1
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.agent.id]
  }

  registry {
    server   = local.registry
    identity = azurerm_user_assigned_identity.agent.id
  }

  template {
    container {
      name   = "agent"
      image  = var.agent_image
      cpu    = 2
      memory = "4Gi"
      args   = ["ask"]
      env {
        name  = "KB_ACCOUNT_URL"
        value = azurerm_storage_account.data.primary_blob_endpoint
      }
      env {
        name  = "KB_CONTAINER"
        value = azurerm_storage_container.c["kb"].name
      }
      env {
        name  = "AZURE_CLIENT_ID"
        value = azurerm_user_assigned_identity.agent.client_id
      }
      env {
        name  = "ORDERS_URL"
        value = "http://127.0.0.1:8081"
      }
      # scripts/ask.sh sets QUESTION and RUN_ID on each execution.
      env {
        name  = "QUESTION"
        value = "What is your return policy?"
      }
    }
  }

  tags       = local.tags
  depends_on = [azurerm_role_assignment.agent_pull, azurerm_monitor_diagnostic_setting.jobs]
}
