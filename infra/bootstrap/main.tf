data "azurerm_client_config" "me" {}

locals {
  # Storage account and registry names are global and allow only lowercase letters and
  # digits. A short hash of the subscription ID makes them unique without a random provider.
  suffix = substr(sha1(var.subscription_id), 0, 6)
  tags   = { lab = "seceng-bootcamp-week-18", project = "sentinel-agent" }
  sub    = "/subscriptions/${var.subscription_id}"
}

# The bootstrap group holds what outlives the lab: Terraform state, the image registry and the
# deploy identity. The lab group starts empty; CI fills it and may change nothing else.
resource "azurerm_resource_group" "bootstrap" {
  name     = "rg-sentinel-bootstrap"
  location = var.location
  tags     = local.tags
}

resource "azurerm_resource_group" "lab" {
  name     = "rg-sentinel-lab"
  location = var.location
  tags     = local.tags
}

# --- Terraform state for the main stack -------------------------------------------------

# trivy:ignore:AZU-0012 GitHub-hosted runners have no fixed address, so the state account keeps a public endpoint; shared keys are off and every request needs an Entra ID token
# trivy:ignore:AZU-0057 Classic Storage Analytics logging; every change to the state account is in the activity log, and the account has no queues
# trivy:ignore:AZU-0058 One-region lab; blob versioning covers a bad write, and geo-replication would double the cost
# trivy:ignore:AZU-0060 Microsoft-managed keys plus infrastructure encryption; a customer key needs a Key Vault with purge protection, which outlives the lab by at least 7 days
resource "azurerm_storage_account" "state" {
  # checkov:skip=CKV_AZURE_206:One-region lab; blob versioning covers a bad write, and geo-replication would double the cost
  # checkov:skip=CKV2_AZURE_33:A private endpoint costs about $7 a month and GitHub-hosted runners could not reach it
  # checkov:skip=CKV_AZURE_59:GitHub-hosted runners have no fixed address; shared keys are off and every request needs an Entra ID token
  # checkov:skip=CKV2_AZURE_1:Microsoft-managed keys plus infrastructure encryption; a customer key needs a Key Vault with purge protection, which outlives the lab by at least 7 days
  # checkov:skip=CKV_AZURE_33:The account has no queues
  name                              = "stsentineltf${local.suffix}"
  resource_group_name               = azurerm_resource_group.bootstrap.name
  location                          = var.location
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
    delete_retention_policy { days = 30 }
    container_delete_retention_policy { days = 30 }
  }
  sas_policy {
    expiration_period = "00.01:00:00"
  }
  tags = local.tags
}

resource "azurerm_storage_container" "state" {
  # checkov:skip=CKV2_AZURE_21:The state account is written only by Terraform; its activity log records each change to the account
  name                  = "tfstate"
  storage_account_id    = azurerm_storage_account.state.id
  container_access_type = "private"
}

# --- Image registry -----------------------------------------------------------------------

resource "azurerm_container_registry" "agent" {
  # checkov:skip=CKV_AZURE_139:Private networking needs the Premium tier (about $50 a month); admin user and anonymous pull are off, so every pull needs an Entra ID token
  # checkov:skip=CKV_AZURE_163:Microsoft Defender for Containers is a paid plan; the pipeline scans every image with Trivy before it pushes
  # checkov:skip=CKV_AZURE_164:Content trust needs the Premium tier; the job pulls the image by digest, which fixes its content
  # checkov:skip=CKV_AZURE_165:Geo-replication needs the Premium tier; one-region lab
  # checkov:skip=CKV_AZURE_166:Quarantine needs the Premium tier; the pipeline scans before it pushes
  # checkov:skip=CKV_AZURE_167:Retention of untagged manifests needs the Premium tier; the pipeline pushes only tagged images
  # checkov:skip=CKV_AZURE_233:Zone redundancy needs the Premium tier
  # checkov:skip=CKV_AZURE_237:Dedicated data endpoints need the Premium tier
  name                    = "crsentinel${local.suffix}"
  resource_group_name     = azurerm_resource_group.bootstrap.name
  location                = var.location
  sku                     = "Basic"
  admin_enabled           = false
  anonymous_pull_enabled  = false
  zone_redundancy_enabled = false
  tags                    = local.tags
}

# --- The GitHub deploy identity -------------------------------------------------------------

resource "azurerm_user_assigned_identity" "deploy" {
  name                = "id-sentinel-deploy"
  resource_group_name = azurerm_resource_group.bootstrap.name
  location            = var.location
  tags                = local.tags
}

# Only a workflow on this repository's main branch can sign in as the deploy identity.
resource "azurerm_federated_identity_credential" "github_main" {
  name                      = "github-main"
  user_assigned_identity_id = azurerm_user_assigned_identity.deploy.id
  issuer                    = "https://token.actions.githubusercontent.com"
  audience                  = ["api://AzureADTokenExchange"]
  subject = format("repo:%s@%s/%s@%s:ref:refs/heads/main", split("/", var.github_repo)[0], var.github_owner_id,
  split("/", var.github_repo)[1], var.github_repo_id)
}

locals {
  deploy = azurerm_user_assigned_identity.deploy.principal_id
  # The only roles CI may grant, and only to service principals (managed identities). This is
  # the Azure counterpart of the AWS permissions boundary: CI can create identities for the
  # lab, but it cannot give any of them, or itself, more than these three read roles.
  grantable = {
    acr_pull             = "7f951dda-4ed3-4680-a7ca-43fe172d538d" # AcrPull
    blob_data_reader     = "2a2b9908-6ea1-4ae2-8e65-a410df84e7d1" # Storage Blob Data Reader
    log_analytics_reader = "73c42c96-874c-492b-b04d-ab87d138a893" # Log Analytics Reader
  }
  grant_condition = <<-EOT
    (
     (
      !(ActionMatches{'Microsoft.Authorization/roleAssignments/write'})
     )
     OR
     (
      @Request[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {${join(", ", values(local.grantable))}}
      AND
      @Request[Microsoft.Authorization/roleAssignments:PrincipalType] ForAnyOfAnyValues:StringEqualsIgnoreCase {'ServicePrincipal'}
     )
    )
    AND
    (
     (
      !(ActionMatches{'Microsoft.Authorization/roleAssignments/delete'})
     )
     OR
     (
      @Resource[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {${join(", ", values(local.grantable))}}
      AND
      @Resource[Microsoft.Authorization/roleAssignments:PrincipalType] ForAnyOfAnyValues:StringEqualsIgnoreCase {'ServicePrincipal'}
     )
    )
  EOT
}

# Build and run everything in the lab group, and write its blobs (seed data).
resource "azurerm_role_assignment" "deploy_lab" {
  for_each             = toset(["Contributor", "Storage Blob Data Contributor"])
  scope                = azurerm_resource_group.lab.id
  role_definition_name = each.value
  principal_id         = local.deploy
  principal_type       = "ServicePrincipal"
}

# Grant the three read roles above, in the lab group and on the registry, and nothing else.
resource "azurerm_role_assignment" "deploy_grant" {
  for_each = {
    lab      = azurerm_resource_group.lab.id
    registry = azurerm_container_registry.agent.id
  }
  scope                = each.value
  role_definition_name = "Role Based Access Control Administrator"
  principal_id         = local.deploy
  principal_type       = "ServicePrincipal"
  condition            = local.grant_condition
  condition_version    = "2.0"
}

resource "azurerm_role_assignment" "deploy_push" {
  scope                = azurerm_container_registry.agent.id
  role_definition_name = "AcrPush"
  principal_id         = local.deploy
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "deploy_state" {
  scope                = azurerm_storage_container.state.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = local.deploy
  principal_type       = "ServicePrincipal"
}

# The subscription's activity log (management events, the CloudTrail counterpart) can be sent
# to the lab's workspace only by a diagnostic setting on the subscription itself. This role
# allows that and nothing else at subscription scope.
resource "azurerm_role_definition" "activity_export" {
  name        = "sentinel-activity-log-export"
  scope       = local.sub
  description = "Manage the subscription's diagnostic settings, for the sentinel-agent lab"
  permissions {
    actions = [
      "Microsoft.Insights/diagnosticSettings/read",
      "Microsoft.Insights/diagnosticSettings/write",
      "Microsoft.Insights/diagnosticSettings/delete",
    ]
  }
  assignable_scopes = [local.sub]
}

resource "azurerm_role_assignment" "deploy_activity" {
  scope              = local.sub
  role_definition_id = azurerm_role_definition.activity_export.role_definition_resource_id
  principal_id       = local.deploy
  principal_type     = "ServicePrincipal"
}

# One Network Watcher per region per subscription. Azure creates one in NetworkWatcherRG the
# first time a virtual network appears, outside CI's reach. Creating it here first, in the lab
# group, lets CI attach VNet flow logs to it.
resource "azurerm_network_watcher" "lab" {
  name                = "nw-sentinel-${var.location}"
  resource_group_name = azurerm_resource_group.lab.name
  location            = var.location
  tags                = local.tags
}
