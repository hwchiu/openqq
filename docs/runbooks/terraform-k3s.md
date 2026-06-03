# Terraform K3s Runbook

## Goal

Provision the Azure VM layer and the base three-node `k3s` cluster repeatably with Terraform.

## Why this path

The shell-based Azure scripts were useful for discovery and debugging, but Terraform is the correct control path for repeatability.

## Workflow

1. Authenticate to Azure
2. Prepare `terraform/terraform.tfvars`
3. Run `make tf-init`
4. Run `make tf-apply`
5. Use Terraform outputs to fetch kubeconfig from the control plane
6. Verify:

```bash
kubectl --kubeconfig generated/kubeconfig get nodes -o wide
```

## Expected result

1. `cp-0` is `Ready`
2. `worker-1` is `Ready`
3. `worker-2` is `Ready`

## Current scope

This Terraform stack provisions the base Kubernetes cluster only.

OpenShell still requires:

1. `agent-sandbox` installation
2. OpenShell Helm chart installation
3. Gateway exposure values for remote CLI access

## Runtime modes

Use `terraform/terraform.tfvars` to select the node runtime:

1. `container_runtime = "containerd"`
2. `container_runtime = "crio"`

`crio` mode installs the external CRI-O service before K3s starts and then points K3s at the CRI socket.
