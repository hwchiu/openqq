SHELL := /bin/bash

.PHONY: preflight repo-tree cluster-up cluster-kubeconfig cluster-status cluster-down tf-init tf-plan tf-apply tf-destroy tf-plan-fuse tf-apply-fuse tf-destroy-fuse openshell-install openshell-patcher openshell-verify openshell-endpoint gvisor-install gvisor-verify openshell-patcher-gvisor kata-prereq kata-install kata-verify openshell-patcher-kata fuse-prereq install-k3s-gvisor install-k3s-openshell-runc install-k3s-openshell-gvisor install-k3s-kubearmor-runc install-comparison-matrix destroy-comparison-matrix

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

tf-plan-fuse:
	terraform -chdir=terraform plan -var-file=terraform.fuse.tfvars

tf-apply-fuse:
	terraform -chdir=terraform apply -var-file=terraform.fuse.tfvars

tf-destroy-fuse:
	terraform -chdir=terraform destroy -var-file=terraform.fuse.tfvars

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

fuse-prereq:
	./scripts/check-fuse-prereqs.sh

install-k3s-gvisor:
	./scripts/install-k3s-gvisor.sh

install-k3s-openshell-runc:
	./scripts/install-k3s-openshell-runc.sh

install-k3s-openshell-gvisor:
	./scripts/install-k3s-openshell-gvisor.sh

install-k3s-kubearmor-runc:
	./scripts/install-k3s-kubearmor-runc.sh

install-comparison-matrix:
	./scripts/install-comparison-matrix.sh

destroy-comparison-matrix:
	./scripts/destroy-comparison-matrix.sh
