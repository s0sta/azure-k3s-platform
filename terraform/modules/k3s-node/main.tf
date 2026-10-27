# One Linux VM for k3s: Ubuntu 24.04 LTS, Trusted Launch, managed identity, Azure Monitor Agent.

variable "name" { type = string }
variable "role" { type = string }
variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "subnet_id" { type = string }
variable "private_ip" { type = string }
variable "size" { type = string }
variable "admin_username" { type = string }
variable "custom_data" { type = string }
variable "tags" { type = map(string) }
variable "ssh_public_key" {
  type      = string
  sensitive = true
}
variable "public_ip" {
  description = "Attach the server public IP (only the server)."
  type        = bool
  default     = false
}
variable "public_ip_id" {
  type    = string
  default = null
}
variable "lb_backend_pool_id" {
  description = "Join this load balancer pool (agents)."
  type        = string
  default     = null
}

resource "azurerm_network_interface" "this" {
  name                = "nic-${var.name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  ip_configuration {
    name                          = "primary"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Static"
    private_ip_address            = var.private_ip
    public_ip_address_id          = var.public_ip ? var.public_ip_id : null
  }
}

resource "azurerm_network_interface_backend_address_pool_association" "this" {
  count                   = var.lb_backend_pool_id == null ? 0 : 1
  network_interface_id    = azurerm_network_interface.this.id
  ip_configuration_name   = "primary"
  backend_address_pool_id = var.lb_backend_pool_id
}

resource "azurerm_linux_virtual_machine" "this" {
  name                            = var.name
  location                        = var.location
  resource_group_name             = var.resource_group_name
  size                            = var.size
  admin_username                  = var.admin_username
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.this.id]
  custom_data                     = base64encode(var.custom_data)
  secure_boot_enabled             = true
  vtpm_enabled                    = true
  patch_mode                      = "ImageDefault"
  tags                            = merge(var.tags, { k3s_role = var.role })

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.ssh_public_key
  }

  os_disk {
    name                 = "osdisk-${var.name}"
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
    disk_size_gb         = 64
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  identity {
    type = "SystemAssigned"
  }

  boot_diagnostics {}
}

resource "azurerm_virtual_machine_extension" "ama" {
  name                       = "AzureMonitorLinuxAgent"
  virtual_machine_id         = azurerm_linux_virtual_machine.this.id
  publisher                  = "Microsoft.Azure.Monitor"
  type                       = "AzureMonitorLinuxAgent"
  type_handler_version       = "1.0"
  auto_upgrade_minor_version = true
  automatic_upgrade_enabled  = true
  tags                       = var.tags
}

output "vm_id" { value = azurerm_linux_virtual_machine.this.id }
output "principal_id" { value = azurerm_linux_virtual_machine.this.identity[0].principal_id }
output "private_ip" { value = azurerm_network_interface.this.private_ip_address }
