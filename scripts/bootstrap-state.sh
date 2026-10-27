#!/usr/bin/env bash
# One-time setup, run by an admin with `az login`:
#  1. a storage account for the Terraform state (versioning, soft delete, TLS 1.2, no public or key access)
#  2. an Entra ID app with a federated credential for GitHub Actions (OIDC, no client secret)
#  3. role assignments: Contributor + User Access Administrator (role assignments for the VMs) on the subscription
set -euo pipefail
REPO=${REPO:-s0sta/azure-k3s-platform}
LOCATION=${LOCATION:-westeurope}
RG=${RG:-rg-tfstate}
SA=${SA:-sttfstate$RANDOM$RANDOM}
SUB=$(az account show --query id -o tsv)
TENANT=$(az account show --query tenantId -o tsv)

az group create -n "$RG" -l "$LOCATION" --tags purpose=terraform-state -o none
az storage account create -n "$SA" -g "$RG" -l "$LOCATION" --sku Standard_ZRS --kind StorageV2 \
  --min-tls-version TLS1_2 --allow-blob-public-access false --allow-shared-key-access false \
  --https-only true -o none
az storage account blob-service-properties update -n "$SA" -g "$RG" \
  --enable-versioning true --enable-delete-retention true --delete-retention-days 30 \
  --enable-container-delete-retention true --container-delete-retention-days 30 -o none
az storage container create -n tfstate --account-name "$SA" --auth-mode login -o none

APP_ID=$(az ad app create --display-name "gh-oidc-${REPO//\//-}" --query appId -o tsv)
az ad sp create --id "$APP_ID" -o none
for subject in "repo:${REPO}:ref:refs/heads/main" "repo:${REPO}:pull_request" "repo:${REPO}:environment:production"; do
  az ad app federated-credential create --id "$APP_ID" --parameters "{
    \"name\": \"gh-$(echo "$subject" | tr ':/' '--' | cut -c1-100)\",
    \"issuer\": \"https://token.actions.githubusercontent.com\",
    \"subject\": \"$subject\",
    \"audiences\": [\"api://AzureADTokenExchange\"]
  }" -o none
done
az role assignment create --assignee "$APP_ID" --role Contributor --scope "/subscriptions/$SUB" -o none
az role assignment create --assignee "$APP_ID" --role "User Access Administrator" --scope "/subscriptions/$SUB" -o none
az role assignment create --assignee "$APP_ID" --role "Storage Blob Data Contributor" \
  --scope "$(az storage account show -n "$SA" -g "$RG" --query id -o tsv)" -o none

cat <<OUT

Done. Add these as GitHub repository variables (Settings → Secrets and variables → Actions → Variables):
  AZURE_CLIENT_ID       = $APP_ID
  AZURE_TENANT_ID       = $TENANT
  AZURE_SUBSCRIPTION_ID = $SUB
  TFSTATE_RG            = $RG
  TFSTATE_ACCOUNT       = $SA
  ADMIN_CIDRS           = ["<your.public.ip>/32"]
  SSH_PUBLIC_KEY        = <contents of ~/.ssh/id_ed25519.pub>
Then create the environment "production" with yourself as required reviewer.
OUT
