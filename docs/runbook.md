# Runbook

## First deployment
1. `az login`, then `make bootstrap` (state storage + OIDC app). Add the printed values as GitHub variables.
2. Copy `terraform/terraform.tfvars.example` to `terraform/terraform.tfvars` and `backend.hcl.example` to
   `backend.hcl`, fill in your IP and SSH key.
3. `make init plan apply` (or open a pull request and let the pipeline do it).
4. `make configure` — hardening, k3s, platform (about 10 minutes).
5. `make kubeconfig && KUBECONFIG=./kubeconfig kubectl get nodes -o wide`.

## Daily checks
- Grafana: `kubectl -n monitoring port-forward svc/monitoring-grafana 3000:80`, user `admin`, password:
  `kubectl -n monitoring get secret grafana-admin -o jsonpath='{.data.admin-password}' | base64 -d`.
- Alerts: `kubectl -n monitoring port-forward svc/monitoring-kube-prometheus-alertmanager 9093`.
- Host logs in Azure: Log Analytics → `Syslog | where SeverityLevel in ("err","crit") | top 50 by TimeGenerated`.

## Patch the nodes
Security updates install by themselves (unattended-upgrades). For a kernel update, reboot one node at a time:
```sh
kubectl drain agent-1 --ignore-daemonsets --delete-emptydir-data
ssh -J azureops@<server-ip> azureops@10.40.1.20 sudo reboot
kubectl uncordon agent-1
```

## Upgrade k3s
Change `k3s_version` in `ansible/group_vars/all.yml`, run the playbook (agents go one by one: `serial: 1`).

## Rotate the join token
`terraform apply -replace=random_password.k3s_token`, then run the playbook; it restarts k3s with the new token.

## Disaster recovery
- Infrastructure: `terraform apply` rebuilds everything from Git.
- Cluster state: k3s keeps SQLite on the server; back it up with
  `sudo k3s etcd-snapshot save` (after switching to embedded etcd with `--cluster-init`) or copy
  `/var/lib/rancher/k3s/server/db/` while k3s is stopped. Apps come back from Git (GitOps).

## Clean up
`make destroy` — deletes the resource group (Key Vault stays soft-deleted for 7 days).
