output "resource_group" {
  value = azurerm_resource_group.this.name
}

output "server_public_ip" {
  description = "SSH and Kubernetes API (only from admin_cidrs)."
  value       = module.network.server_public_ip
}

output "ingress_public_ip" {
  description = "HTTP/HTTPS entry point (Azure Load Balancer → agents)."
  value       = module.network.ingress_public_ip
}

output "ssh" {
  value = "ssh ${var.admin_username}@${module.network.server_public_ip}"
}

output "key_vault_name" {
  value = azurerm_key_vault.this.name
}

output "log_analytics_workspace_id" {
  value = azurerm_log_analytics_workspace.this.workspace_id
}
