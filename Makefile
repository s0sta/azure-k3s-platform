# Run `make help`.
.PHONY: help bootstrap init plan apply configure kubeconfig lint destroy
help:          ## show this help
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-11s %s\n", $$1, $$2}'
bootstrap:     ## one time: state storage + GitHub OIDC app in Azure
	./scripts/bootstrap-state.sh
init:          ## terraform init with the remote state (needs terraform/backend.hcl)
	cd terraform && terraform init -backend-config=backend.hcl
plan:          ## terraform plan
	cd terraform && terraform plan -out=tfplan
apply:         ## terraform apply the saved plan (writes ansible/inventory/hosts.ini)
	cd terraform && terraform apply tfplan
configure:     ## harden the nodes, install k3s and the platform
	cd ansible && ansible-galaxy collection install -r requirements.yml && ansible-playbook playbooks/site.yml
kubeconfig:    ## copy the kubeconfig to ./kubeconfig (API only reachable from admin_cidrs)
	ssh $$(cd terraform && terraform output -raw ssh | cut -d' ' -f2) sudo cat /etc/rancher/k3s/k3s.yaml \
	  | sed "s/127.0.0.1/$$(cd terraform && terraform output -raw server_public_ip)/" > kubeconfig && chmod 600 kubeconfig
lint:          ## the same checks as CI
	cd terraform && terraform fmt -check -recursive && terraform validate && tflint --recursive
	cd ansible && yamllint . && ansible-lint --profile production playbooks/site.yml
destroy:       ## delete everything (asks first)
	cd terraform && terraform destroy
