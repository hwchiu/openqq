# Comparison Stacks

This directory contains four independent Terraform roots for side-by-side Azure lab environments.

## Stacks

1. `k3s-gvisor`
2. `k3s-openshell-runc`
3. `k3s-openshell-gvisor`
4. `k3s-kubearmor-runc`

Each stack has its own Terraform state, Azure resource group, CIDR range, and post-install script path.

## Shared inputs

You can provide shared Azure inputs in either of these ways:

1. `terraform/stacks/common.auto.tfvars`
2. Environment variables:
   - `AZURE_SUBSCRIPTION_ID`
   - `AZURE_TENANT_ID`
   - `AZURE_LOCATION`
   - `AZURE_ADMIN_USERNAME`
   - `AZURE_SSH_PUBLIC_KEY`
   - or `AZURE_SSH_PUBLIC_KEY_PATH`
3. Existing `terraform/terraform.tfvars` in the repo root; the helper scripts extract only the shared keys.

See `common.auto.tfvars.example` for the expected shape.
