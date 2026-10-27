# Architecture

```mermaid
flowchart TB
  admin[Admin laptop<br/>admin_cidrs only] -->|SSH 22, API 6443| pipS[Public IP: server]
  users[Users] -->|80 / 443| lb[Azure Standard Load Balancer]
  subgraph Azure["Azure subscription — rg-k3s-lab"]
    subgraph VNet["VNet 10.40.0.0/16 — subnet 10.40.1.0/24 + NSG (deny by default)"]
      server[k3s server<br/>control plane, tainted<br/>10.40.1.10]
      a1[k3s agent 1<br/>10.40.1.20]
      a2[k3s agent 2<br/>10.40.1.21]
    end
    nat[NAT gateway<br/>all outbound traffic]
    kv[Key Vault<br/>k3s join token, RBAC]
    law[Log Analytics<br/>syslog via Azure Monitor Agent + DCR]
    budget[Budget alert]
  end
  pipS --> server
  lb --> a1 & a2
  server & a1 & a2 --> nat
  server & a1 & a2 -.managed identity.-> kv
  server & a1 & a2 -.AMA.-> law
  subgraph K8s["Inside the cluster"]
    traefik[Traefik ingress] --> apps[Apps]
    prom[Prometheus + Alertmanager] --> graf[Grafana]
    fb[Fluent Bit] --> loki[Loki]
    cm[cert-manager]
  end
  a1 & a2 --- K8s
```

## Layers
| Layer | Tool | What it does |
|---|---|---|
| Infrastructure | Terraform (azurerm 4) | VNet, NSG, NAT gateway, Load Balancer, 3 VMs (Trusted Launch), Key Vault, Log Analytics, DCR, budget |
| First boot | cloud-init | patches, no password login, no root login |
| Configuration | Ansible | OS hardening, k3s server and agents, platform charts |
| Platform | Helm (via Ansible) | cert-manager, kube-prometheus-stack, Loki, Fluent Bit, alert rules |
| Delivery | GitHub Actions | fmt/validate/tflint/Trivy → plan on PR → apply after approval; nightly drift check; ansible-lint |

## Network rules
- Inbound from the internet: only 80/443 to the load balancer (agents run the Traefik ingress).
- SSH (22) and the Kubernetes API (6443): only from `admin_cidrs`, only on the server's public IP.
  Agents have no public IP; Ansible reaches them through the server (`ProxyJump`).
- Outbound: one NAT gateway (fixed egress IP, no default outbound access on the subnet).
- Pod-to-pod traffic between nodes is encrypted (`flannel-backend: wireguard-native`).

## Cost (West Europe, pay-as-you-go, about)
3 × B2s VMs ≈ 3 × €33, NAT gateway ≈ €32 + traffic, Standard LB ≈ €18, 3 public IPs ≈ €10, disks ≈ €15,
Log Analytics (1 GB/day cap) a few €. About **€150–180 per month** if it runs all the time.
`terraform destroy` after a demo, or deallocate the VMs; the budget alert warns at 80 % of `monthly_budget`.
