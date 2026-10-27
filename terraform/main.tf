data "azurerm_client_config" "current" {}

locals {
  name = "${var.project}-${var.environment}"
  tags = merge({ project = var.project, environment = var.environment, managed_by = "terraform" }, var.tags)
}

resource "azurerm_resource_group" "this" {
  name     = "rg-${local.name}"
  location = var.location
  tags     = local.tags
}

# ---------- logs ----------
resource "azurerm_log_analytics_workspace" "this" {
  name                = "log-${local.name}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  daily_quota_gb      = 1
  tags                = local.tags
}

# ---------- network ----------
module "network" {
  source              = "./modules/network"
  name                = local.name
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  address_space       = var.address_space
  admin_cidrs         = var.admin_cidrs
  web_cidrs           = length(var.web_cidrs) > 0 ? var.web_cidrs : var.admin_cidrs
  tags                = local.tags
}

# ---------- secrets ----------
resource "random_password" "k3s_token" {
  length  = 48
  special = false
}

resource "random_string" "kv" {
  length  = 5
  upper   = false
  special = false
}

resource "azurerm_key_vault" "this" {
  name                       = "kv-${local.name}-${random_string.kv.result}"
  location                   = azurerm_resource_group.this.location
  resource_group_name        = azurerm_resource_group.this.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  enable_rbac_authorization  = true
  purge_protection_enabled   = true
  soft_delete_retention_days = 7
  tags                       = local.tags
}

resource "azurerm_role_assignment" "kv_deployer" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_key_vault_secret" "k3s_token" {
  name         = "k3s-token"
  value        = random_password.k3s_token.result
  key_vault_id = azurerm_key_vault.this.id
  content_type = "k3s cluster join token"
  depends_on   = [azurerm_role_assignment.kv_deployer]
}

# ---------- nodes ----------
module "server" {
  source              = "./modules/k3s-node"
  name                = "vm-${local.name}-server"
  role                = "server"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  subnet_id           = module.network.subnet_id
  private_ip          = cidrhost(module.network.subnet_prefix, 10)
  public_ip           = true
  public_ip_id        = module.network.server_public_ip_id
  size                = var.server_size
  admin_username      = var.admin_username
  ssh_public_key      = var.ssh_public_key
  custom_data         = templatefile("${path.module}/templates/cloud-init.yaml.tftpl", { admin_username = var.admin_username, role = "server" })
  tags                = local.tags
}

module "agent" {
  source              = "./modules/k3s-node"
  count               = var.agent_count
  name                = "vm-${local.name}-agent-${count.index + 1}"
  role                = "agent"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  subnet_id           = module.network.subnet_id
  private_ip          = cidrhost(module.network.subnet_prefix, 20 + count.index)
  public_ip           = false
  lb_backend_pool_id  = module.network.lb_backend_pool_id
  size                = var.agent_size
  admin_username      = var.admin_username
  ssh_public_key      = var.ssh_public_key
  custom_data         = templatefile("${path.module}/templates/cloud-init.yaml.tftpl", { admin_username = var.admin_username, role = "agent" })
  tags                = local.tags
}

# the nodes may read the join token (and nothing else)
resource "azurerm_role_assignment" "kv_nodes" {
  for_each             = { for i, id in concat([module.server.principal_id], module.agent[*].principal_id) : tostring(i) => id }
  scope                = azurerm_key_vault_secret.k3s_token.resource_versionless_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = each.value
}

# ---------- Azure Monitor: syslog of all nodes to Log Analytics ----------
resource "azurerm_monitor_data_collection_rule" "syslog" {
  name                = "dcr-${local.name}-syslog"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags

  destinations {
    log_analytics {
      name                  = "law"
      workspace_resource_id = azurerm_log_analytics_workspace.this.id
    }
  }
  data_flow {
    streams      = ["Microsoft-Syslog"]
    destinations = ["law"]
  }
  data_sources {
    syslog {
      name           = "syslog"
      streams        = ["Microsoft-Syslog"]
      facility_names = ["auth", "authpriv", "daemon", "kern", "syslog"]
      log_levels     = ["Warning", "Error", "Critical", "Alert", "Emergency"]
    }
  }
}

resource "azurerm_monitor_data_collection_rule_association" "nodes" {
  for_each                = { for i, id in concat([module.server.vm_id], module.agent[*].vm_id) : tostring(i) => id }
  name                    = "dcra-${each.key}"
  target_resource_id      = each.value
  data_collection_rule_id = azurerm_monitor_data_collection_rule.syslog.id
}

# ---------- cost guard ----------
resource "azurerm_consumption_budget_resource_group" "this" {
  count             = var.monthly_budget > 0 && length(var.budget_emails) > 0 ? 1 : 0
  name              = "budget-${local.name}"
  resource_group_id = azurerm_resource_group.this.id
  amount            = var.monthly_budget
  time_grain        = "Monthly"

  time_period {
    start_date = var.budget_start_date
  }

  notification {
    enabled        = true
    threshold      = 80
    operator       = "GreaterThan"
    threshold_type = "Forecasted"
    contact_emails = var.budget_emails
  }

  lifecycle {
    ignore_changes = [time_period]
  }
}

# ---------- Ansible inventory, written for the next step ----------
resource "local_file" "inventory" {
  filename        = "${path.module}/../ansible/inventory/hosts.ini"
  file_permission = "0644"
  content = templatefile("${path.module}/templates/hosts.ini.tftpl", {
    admin_username = var.admin_username
    server_public  = module.network.server_public_ip
    server_private = module.server.private_ip
    agents         = module.agent[*].private_ip
    ingress_ip     = module.network.ingress_public_ip
    key_vault      = azurerm_key_vault.this.name
  })
}
