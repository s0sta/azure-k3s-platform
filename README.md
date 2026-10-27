# Azure k3s platform

[![terraform](https://github.com/s0sta/azure-k3s-platform/actions/workflows/terraform.yml/badge.svg)](https://github.com/s0sta/azure-k3s-platform/actions/workflows/terraform.yml)
[![ansible](https://github.com/s0sta/azure-k3s-platform/actions/workflows/ansible.yml/badge.svg)](https://github.com/s0sta/azure-k3s-platform/actions/workflows/ansible.yml)
![License: MIT](https://img.shields.io/badge/license-MIT-blue)

A small, production-style Kubernetes platform on Azure, built **only from code**:
**Terraform** creates the network, VMs, Key Vault and monitoring; **Ansible** hardens the servers and installs
**k3s**; Helm charts add **cert-manager, Prometheus, Grafana, Loki and Fluent Bit**. GitHub Actions runs every
change through checks, a reviewed plan and an approved apply — logged in to Azure with **OIDC, without secrets**.

## What it shows

| Area | How |
|---|---|
| Infrastructure as Code | Terraform (azurerm 4), two modules (network, node), remote state in Azure Storage with Entra ID auth |
| Networking | VNet + NSG (deny by default), NAT gateway egress, Standard Load Balancer for 80/443 (closed to the world until you set `web_cidrs`), admin access only from your IP |
| Identity and secrets | GitHub OIDC (workload identity federation), VM managed identities, k3s token in Key Vault |
| Configuration management | Ansible roles (hardening, k3s, platform), `ansible-lint` production profile |
| Hardening | sshd, sysctl, auditd, fail2ban, unattended upgrades; k3s secrets encryption, PSA, audit log, WireGuard pod network |
| Observability | Prometheus, Alertmanager, Grafana, Loki, Fluent Bit, custom alert rules, Azure Monitor (syslog → Log Analytics) |
| CI/CD for infra | fmt → validate → tflint → Trivy → plan comment on the PR → apply after approval; nightly drift issue |
| Cost control | budget with forecast alert, small VM sizes, log cap, one-command destroy |

Details: [architecture](docs/architecture.md) · [security](docs/security.md) · [runbook](docs/runbook.md)

## Quick start

```sh
az login && make bootstrap                 # once: state storage + OIDC app (prints the GitHub variables)
cp terraform/terraform.tfvars.example terraform/terraform.tfvars   # your IP and SSH key
cp terraform/backend.hcl.example terraform/backend.hcl
make init plan apply                       # Azure resources (also writes the Ansible inventory)
make configure                             # hardening + k3s + platform
make kubeconfig && KUBECONFIG=./kubeconfig kubectl get nodes
```

## Layout

```
terraform/            root module, modules/network, modules/k3s-node, cloud-init and inventory templates
ansible/              roles: hardening, k3s, platform (Helm values, alert rules)
.github/workflows/    terraform.yml (checks, plan, apply), drift.yml (nightly), ansible.yml (lint)
scripts/              bootstrap-state.sh (state storage + GitHub OIDC)
docs/                 architecture, security, runbook
```

## Notes
- Running it all the time costs about €150–180/month (see [architecture](docs/architecture.md#cost-west-europe-pay-as-you-go-about)).
  Run `make destroy` after a demo.
- The same Ansible roles work on any Ubuntu 24.04 VMs (home lab, Proxmox): write the inventory by hand and skip Terraform.

---
Built by [Hosam Hani](https://s0sta.com) · MIT license
