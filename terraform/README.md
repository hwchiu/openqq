# Terraform Stack

This directory contains a Terraform implementation for a repeatable Azure-backed three-node `k3s` cluster.

## What it provisions

1. Resource group
2. VNet and subnet
3. Shared NSG with SSH and Kubernetes API rules
4. Three public IPs
5. Three NICs
6. One control-plane VM
7. Two worker VMs
8. `k3s` bootstrap via cloud-init

## Files

1. [versions.tf](/Users/hwchiu/hwchiu/openqq/terraform/versions.tf)
2. [providers.tf](/Users/hwchiu/hwchiu/openqq/terraform/providers.tf)
3. [variables.tf](/Users/hwchiu/hwchiu/openqq/terraform/variables.tf)
4. [main.tf](/Users/hwchiu/hwchiu/openqq/terraform/main.tf)
5. [outputs.tf](/Users/hwchiu/hwchiu/openqq/terraform/outputs.tf)
6. [terraform.tfvars.example](/Users/hwchiu/hwchiu/openqq/terraform/terraform.tfvars.example)
7. `templates/cloud-init-server.yaml.tftpl`
8. `templates/cloud-init-agent.yaml.tftpl`

## Usage

1. Copy `terraform.tfvars.example` to `terraform.tfvars`
2. Replace `ssh_public_key` with the actual public key contents
3. Run:

```bash
terraform -chdir=terraform init
terraform -chdir=terraform apply
```

4. Fetch kubeconfig from the control plane using the output command
5. Replace `127.0.0.1` in the fetched kubeconfig with the control-plane public IP

## Design note

The Azure node network CIDR is intentionally separated from the `k3s` pod and service CIDRs. This avoids the overlap bug that broke the earlier shell-driven cluster build.
