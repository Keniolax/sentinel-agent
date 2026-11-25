# The SIEM: Wazuh manager and indexer from home-soc-lab on one VM. No inbound port at all.
# An operator reaches it with Run Command (scripts/verify-siem.sh), which goes through the
# VM agent's outbound connection.

locals {
  siem_root = "${path.module}/../../siem"
}

resource "azurerm_public_ip" "siem" {
  name                = "pip-sentinel-siem"
  resource_group_name = local.rg
  location            = local.location
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.tags
}

# trivy:ignore:AZU-0068 The NSG is attached to the SIEM subnet (azurerm_subnet_network_security_group_association.siem), which covers this interface
# trivy:ignore:AZU-0076 The public IP is the VM's only way out (a NAT gateway costs about $32 a month); the NSG drops every inbound packet
resource "azurerm_network_interface" "siem" {
  # checkov:skip=CKV_AZURE_119:The public IP is the VM's only way out (a NAT gateway costs about $32 a month); the NSG drops every inbound packet
  name                = "nic-sentinel-siem"
  resource_group_name = local.rg
  location            = local.location
  ip_configuration {
    name                          = "primary"
    subnet_id                     = azurerm_subnet.siem.id
    private_ip_address_allocation = "Dynamic"
    # Outbound only: the subnet has no default outbound access and no NAT gateway, and the
    # NSG drops every inbound packet.
    public_ip_address_id = azurerm_public_ip.siem.id
  }
  tags = local.tags
}

resource "azurerm_linux_virtual_machine" "siem" {
  # checkov:skip=CKV_AZURE_50:Run Command, the only way in, needs VM extension operations; there is no SSH or other inbound path
  name                            = "vm-sentinel-siem"
  resource_group_name             = local.rg
  location                        = local.location
  size                            = var.siem_vm_size
  network_interface_ids           = [azurerm_network_interface.siem.id]
  admin_username                  = "sentinel"
  disable_password_authentication = true
  allow_extension_operations      = true
  provision_vm_agent              = true
  encryption_at_host_enabled      = true
  secure_boot_enabled             = true
  vtpm_enabled                    = true
  disk_controller_type            = "NVMe"

  # Azure requires an admin key. Its private half was deleted when it was made, and the NSG
  # blocks port 22, so nobody can sign in with it.
  admin_ssh_key {
    username   = "sentinel"
    public_key = file("${local.siem_root}/admin_key.pub")
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.siem.id]
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = 64
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  boot_diagnostics {}

  # Custom data holds base64 copies of siem/ files from this repository and two IDs, none of
  # them secret. The Wazuh passwords are generated on the VM by init-env.sh.
  custom_data = base64encode(templatefile("${local.siem_root}/bootstrap.sh.tftpl", {
    compose_b64      = filebase64("${local.siem_root}/compose.sentinel.yaml")
    config_b64       = filebase64("${local.siem_root}/sentinel-config.sh")
    rules_b64        = filebase64("${local.siem_root}/local_rules.xml")
    collector_b64    = filebase64("${local.siem_root}/collector.py")
    workspace_id     = azurerm_log_analytics_workspace.lab.workspace_id
    client_id        = azurerm_user_assigned_identity.siem.client_id
    home_soc_lab_ref = var.home_soc_lab_ref
  }))

  tags = local.tags
}
