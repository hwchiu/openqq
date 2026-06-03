SHELL := /bin/bash

.PHONY: preflight repo-tree cluster-up cluster-kubeconfig cluster-status cluster-down tf-init tf-plan tf-apply tf-destroy openshell-install openshell-patcher openshell-verify openshell-endpoint

preflight:
	./scripts/check-azure-connectivity.sh

repo-tree:
	@find . -maxdepth 2 -type f | sort

cluster-up:
	./scripts/create-k3s-cluster.sh

cluster-kubeconfig:
	./scripts/fetch-kubeconfig.sh

cluster-status:
	./scripts/kubectl-status.sh

cluster-down:
	./scripts/destroy-k3s-cluster.sh

tf-init:
	terraform -chdir=terraform init

tf-plan:
	terraform -chdir=terraform plan

tf-apply:
	terraform -chdir=terraform apply

tf-destroy:
	terraform -chdir=terraform destroy

openshell-install:
	./scripts/install-openshell-stack.sh

openshell-patcher:
	./scripts/install-openshell-sandbox-patcher.sh

openshell-verify:
	./scripts/verify-openshell-runtime.sh

openshell-endpoint:
	./scripts/get-openshell-endpoint.sh
