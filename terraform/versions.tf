terraform {
  required_version = ">= 1.9.0"
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 4.10" }
    random  = { source = "hashicorp/random", version = "~> 3.6" }
    local   = { source = "hashicorp/local", version = "~> 2.5" }
  }
  # Remote state in Azure Storage (created by scripts/bootstrap-state.sh).
  # Values come from backend.hcl:  terraform init -backend-config=backend.hcl
  backend "azurerm" {
    use_azuread_auth = true
  }
}

provider "azurerm" {
  # subscription_id comes from ARM_SUBSCRIPTION_ID; CI logs in with OIDC (ARM_USE_OIDC=true)
  features {
    key_vault { purge_soft_delete_on_destroy = false }
    resource_group { prevent_deletion_if_contains_resources = true }
  }
  storage_use_azuread = true
}
