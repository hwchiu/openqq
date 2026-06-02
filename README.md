# Azure VM + Kubernetes + NVIDIA Sandbox Plan

This repository contains the planning and handoff material for:

1. Creating Azure VMs
2. Building a Kubernetes cluster on those VMs
3. Installing the NVIDIA software stack required to test a sandbox environment

Start with [docs/azure-connectivity-checklist.md](/Users/hwchiu/hwchiu/openqq/docs/azure-connectivity-checklist.md), then continue to [docs/implementation-plan.md](/Users/hwchiu/hwchiu/openqq/docs/implementation-plan.md) and [docs/information-needed.md](/Users/hwchiu/hwchiu/openqq/docs/information-needed.md).

## Current status

This repo currently contains planning plus implementation scaffolding. No infrastructure code has been applied yet.

## First gate

Do not start provisioning until Azure connectivity and authorization are verified.

Use [docs/azure-connectivity-checklist.md](/Users/hwchiu/hwchiu/openqq/docs/azure-connectivity-checklist.md) first.

## Preferred control path

Prefer Azure MCP for discovery, validation, and provisioning orchestration if an Azure MCP server is configured in the runtime where the next model will execute.

Use Azure CLI only as a fallback when Azure MCP is unavailable.

## Scaffolded entry points

1. [env/azure.env.example](/Users/hwchiu/hwchiu/openqq/env/azure.env.example)
2. [scripts/check-azure-connectivity.sh](/Users/hwchiu/hwchiu/openqq/scripts/check-azure-connectivity.sh)
3. [scripts/create-k3s-cluster.sh](/Users/hwchiu/hwchiu/openqq/scripts/create-k3s-cluster.sh)
4. [scripts/fetch-kubeconfig.sh](/Users/hwchiu/hwchiu/openqq/scripts/fetch-kubeconfig.sh)
5. [scripts/kubectl-status.sh](/Users/hwchiu/hwchiu/openqq/scripts/kubectl-status.sh)
6. [docs/runbooks/preflight.md](/Users/hwchiu/hwchiu/openqq/docs/runbooks/preflight.md)
7. [terraform/README.md](/Users/hwchiu/hwchiu/openqq/terraform/README.md)
8. [k8s/README.md](/Users/hwchiu/hwchiu/openqq/k8s/README.md)
9. [docs/openshell-compatibility.md](/Users/hwchiu/hwchiu/openqq/docs/openshell-compatibility.md)
10. [docs/runbooks/terraform-k3s.md](/Users/hwchiu/hwchiu/openqq/docs/runbooks/terraform-k3s.md)
11. [docs/runbooks/security-comparison.md](/Users/hwchiu/hwchiu/openqq/docs/runbooks/security-comparison.md)

## Important ambiguity

The phrase `openshell from NVIDIA` is ambiguous. Before implementation, the next agent should confirm the exact NVIDIA product, for example:

- `NVIDIA GPU Operator`
- `NVIDIA Container Toolkit`
- `NVIDIA vGPU / driver stack`
- `NVIDIA AI Enterprise / NIM / NeMo / other sandbox workload`
- `OpenShift` instead of `openshell`

That decision is called out in the docs because it changes the VM type, OS image, Kubernetes setup, and installation steps.
