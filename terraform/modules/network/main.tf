# VNet, one node subnet with an NSG, a NAT gateway for outbound traffic,
# a public Standard Load Balancer for HTTP/HTTPS to the agents, and a public IP for the server (admin only).

variable "name" { type = string }
variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "address_space" { type = string }
variable "admin_cidrs" { type = list(string) }
variable "tags" { type = map(string) }

locals {
  subnet_prefix = cidrsubnet(var.address_space, 8, 1) # 10.40.1.0/24
}

resource "azurerm_virtual_network" "this" {
  name                = "vnet-${var.name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = [var.address_space]
  tags                = var.tags
}

resource "azurerm_subnet" "nodes" {
  name                            = "snet-nodes"
  resource_group_name             = var.resource_group_name
  virtual_network_name            = azurerm_virtual_network.this.name
  address_prefixes                = [local.subnet_prefix]
  default_outbound_access_enabled = false
}

resource "azurerm_network_security_group" "nodes" {
  name                = "nsg-${var.name}-nodes"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  security_rule {
    name                       = "allow-ssh-admin"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_address_prefixes    = var.admin_cidrs
    source_port_range          = "*"
    destination_address_prefix = "*"
    destination_port_range     = "22"
  }
  security_rule {
    name                       = "allow-kube-api-admin"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_address_prefixes    = var.admin_cidrs
    source_port_range          = "*"
    destination_address_prefix = "*"
    destination_port_range     = "6443"
  }
  security_rule {
    name                       = "allow-web"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_address_prefix      = "Internet"
    source_port_range          = "*"
    destination_address_prefix = "*"
    destination_port_ranges    = ["80", "443"]
  }
  security_rule {
    name                       = "allow-lb-probe"
    priority                   = 210
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_address_prefix      = "AzureLoadBalancer"
    source_port_range          = "*"
    destination_address_prefix = "*"
    destination_port_ranges    = ["80", "443"]
  }
  security_rule {
    name                       = "allow-intra-subnet"
    priority                   = 300
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_address_prefix      = local.subnet_prefix
    source_port_range          = "*"
    destination_address_prefix = local.subnet_prefix
    destination_port_range     = "*"
  }
  security_rule {
    name                       = "deny-all-inbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_address_prefix      = "*"
    source_port_range          = "*"
    destination_address_prefix = "*"
    destination_port_range     = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "nodes" {
  subnet_id                 = azurerm_subnet.nodes.id
  network_security_group_id = azurerm_network_security_group.nodes.id
}

# outbound internet for all nodes through one NAT gateway (no default outbound access)
resource "azurerm_public_ip" "nat" {
  name                = "pip-${var.name}-nat"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_nat_gateway" "this" {
  name                    = "ng-${var.name}"
  location                = var.location
  resource_group_name     = var.resource_group_name
  sku_name                = "Standard"
  idle_timeout_in_minutes = 10
  tags                    = var.tags
}

resource "azurerm_nat_gateway_public_ip_association" "this" {
  nat_gateway_id       = azurerm_nat_gateway.this.id
  public_ip_address_id = azurerm_public_ip.nat.id
}

resource "azurerm_subnet_nat_gateway_association" "nodes" {
  subnet_id      = azurerm_subnet.nodes.id
  nat_gateway_id = azurerm_nat_gateway.this.id
}

# admin entry point (SSH, Kubernetes API) on the server node
resource "azurerm_public_ip" "server" {
  name                = "pip-${var.name}-server"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

# public HTTP/HTTPS → ingress (Traefik) on the agents
resource "azurerm_public_ip" "ingress" {
  name                = "pip-${var.name}-ingress"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_lb" "ingress" {
  name                = "lbe-${var.name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "Standard"
  tags                = var.tags

  frontend_ip_configuration {
    name                 = "public"
    public_ip_address_id = azurerm_public_ip.ingress.id
  }
}

resource "azurerm_lb_backend_address_pool" "agents" {
  name            = "agents"
  loadbalancer_id = azurerm_lb.ingress.id
}

resource "azurerm_lb_probe" "http" {
  name            = "tcp-80"
  loadbalancer_id = azurerm_lb.ingress.id
  protocol        = "Tcp"
  port            = 80
}

resource "azurerm_lb_rule" "web" {
  for_each                       = toset(["80", "443"])
  name                           = "tcp-${each.key}"
  loadbalancer_id                = azurerm_lb.ingress.id
  protocol                       = "Tcp"
  frontend_port                  = tonumber(each.key)
  backend_port                   = tonumber(each.key)
  frontend_ip_configuration_name = "public"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.agents.id]
  probe_id                       = azurerm_lb_probe.http.id
  disable_outbound_snat          = true
}

output "subnet_id" { value = azurerm_subnet.nodes.id }
output "subnet_prefix" { value = local.subnet_prefix }
output "server_public_ip_id" { value = azurerm_public_ip.server.id }
output "server_public_ip" { value = azurerm_public_ip.server.ip_address }
output "ingress_public_ip" { value = azurerm_public_ip.ingress.ip_address }
output "lb_backend_pool_id" { value = azurerm_lb_backend_address_pool.agents.id }
