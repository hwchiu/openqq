SHELL := /bin/bash

.PHONY: preflight repo-tree cluster-up cluster-kubeconfig cluster-status cluster-down tf-init tf-plan tf-apply tf-destroy openshell-install openshell-patcher openshell-verify openshell-endpoint gvisor-install gvisor-verify openshell-patcher-gvisor kata-prereq kata-install kata-verify openshell-patcher-kata

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

gvisor-install:
	./scripts/install-gvisor.sh

gvisor-verify:
	./scripts/verify-gvisor-runtime.sh

openshell-patcher-gvisor:
	./scripts/install-openshell-sandbox-patcher-gvisor.sh

kata-prereq:
	./scripts/check-kata-prereqs.sh

kata-install:
	./scripts/install-kata.sh

kata-verify:
	./scripts/verify-kata-runtime.sh

openshell-patcher-kata:
	./scripts/install-openshell-sandbox-patcher-kata.sh
