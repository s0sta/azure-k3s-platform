variable "project" {
  description = "Short name used in all resource names."
  type        = string
  default     = "k3s"
  validation {
    condition     = can(regex("^[a-z0-9]{2,8}$", var.project))
    error_message = "2-8 lowercase letters or digits."
  }
}

variable "environment" {
  description = "Environment name (lab, dev, prod)."
  type        = string
  default     = "lab"
}

variable "location" {
  description = "Azure region."
  type        = string
  default     = "westeurope"
}

variable "admin_cidrs" {
  description = "Public IP ranges that may reach SSH (22) and the Kubernetes API (6443). Never 0.0.0.0/0."
  type        = list(string)
  validation {
    condition     = length(var.admin_cidrs) > 0 && !contains(var.admin_cidrs, "0.0.0.0/0")
    error_message = "Give at least one admin CIDR and never 0.0.0.0/0."
  }
}

variable "web_cidrs" {
  description = "Public IP ranges that may open the websites (80/443). Empty = only admin_cidrs (closed lab). Set [\"0.0.0.0/0\"] to go public."
  type        = list(string)
  default     = []
}

variable "admin_username" {
  type    = string
  default = "azureops"
}

variable "ssh_public_key" {
  description = "SSH public key (ed25519) for the admin user."
  type        = string
  sensitive   = true
}

variable "agent_count" {
  description = "Number of k3s agent (worker) nodes."
  type        = number
  default     = 2
  validation {
    condition     = var.agent_count >= 1 && var.agent_count <= 5
    error_message = "1 to 5 agents."
  }
}

variable "server_size" {
  type    = string
  default = "Standard_B2s"
}

variable "agent_size" {
  type    = string
  default = "Standard_B2s"
}

variable "address_space" {
  type    = string
  default = "10.40.0.0/16"
}

variable "monthly_budget" {
  description = "Monthly budget in the billing currency. 0 = no budget."
  type        = number
  default     = 60
}

variable "budget_start_date" {
  description = "First month of the budget (first day of a month, RFC 3339). Changes later are ignored."
  type        = string
  default     = "2026-11-01T00:00:00Z"
  validation {
    condition     = can(regex("^20[0-9]{2}-[01][0-9]-01T00:00:00Z$", var.budget_start_date))
    error_message = "Use the first day of a month, like 2026-11-01T00:00:00Z."
  }
}

variable "budget_emails" {
  description = "E-mail addresses for budget alerts (empty = no budget alerts)."
  type        = list(string)
  default     = []
}

variable "tags" {
  type    = map(string)
  default = {}
}
