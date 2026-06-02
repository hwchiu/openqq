# Implementation Plan

## Goal

Provision Azure virtual machines, install Kubernetes on top of them, then install the NVIDIA components needed for sandbox testing.

## Phase 0: Azure connectivity preflight

Before requirements gathering is considered complete, verify that the operator or automation has working Azure connectivity and enough authorization to create the target resources.

Use [docs/azure-connectivity-checklist.md](/Users/hwchiu/hwchiu/openqq/docs/azure-connectivity-checklist.md).

### Preferred method

1. Use Azure MCP if it is configured in the execution environment
2. Fall back to Azure CLI only if Azure MCP is not available

### Exit criteria

1. Authentication to Azure succeeds
2. The correct subscription is visible and selectable
3. The target region can be queried
4. Required resource providers are accessible
5. Quota and SKU availability can be inspected
6. The chosen identity has permission to create resource groups, networking, compute, and public IP resources if needed

## Recommended execution model

Use infrastructure-as-code from the start. The cleanest path is:

1. Azure MCP for environment discovery and guarded cloud operations if available
2. Terraform for Azure infrastructure
3. `kubeadm` for Kubernetes bootstrap on raw VMs
4. Helm manifests for NVIDIA and sandbox-related components
5. Markdown runbooks for any manual steps that cannot be fully automated

This avoids portal-only drift and makes it easier for another model or engineer to continue.

## Proposed repository layout

The next implementation pass should create and fill these paths:

1. `terraform/`
2. `ansible/` or `scripts/`
3. `k8s/`
4. `docs/runbooks/`
5. `.env.example` or `terraform.tfvars.example`

## Phase 1: Confirm requirements

Before provisioning anything, confirm:

1. Azure subscription and tenant to use
2. Region
3. VM count
4. Control plane topology
5. Worker node count
6. GPU requirement
7. OS image
8. Kubernetes version target
9. Network model
10. Sandbox workload definition
11. Exact NVIDIA product to install
12. Budget and quota limits

## Phase 2: Azure infrastructure

Create the following Azure resources:

1. Resource group
2. Virtual network
3. Subnet or subnets
4. Network security groups
5. Public IPs only if required
6. Load balancer if a stable API endpoint is needed
7. VM instances
8. Managed disks if default disk sizing is insufficient
9. Optional bastion or jump host
10. Optional private DNS records

### VM baseline

Recommended baseline for a small non-production cluster:

1. `1` control plane VM for a lab, or `3` for HA
2. `2+` worker VMs
3. Ubuntu `22.04 LTS` unless NVIDIA compatibility requires another image
4. One GPU-capable worker pool only if the sandbox actually needs GPU

### Azure decisions that affect everything later

1. Whether inbound SSH is allowed from the public internet
2. Whether Kubernetes API should be private or public
3. Whether outbound internet access is allowed from the nodes
4. Whether a NAT gateway, proxy, or private registry is required
5. Whether the subscription has GPU quota in the selected region

## Phase 3: Kubernetes installation

On the VMs:

1. Install container runtime
2. Disable swap
3. Configure kernel modules and sysctls
4. Install `kubeadm`, `kubelet`, and `kubectl`
5. Bootstrap the control plane
6. Join workers
7. Install a CNI plugin such as `Cilium` or `Calico`
8. Install ingress only if the sandbox needs north-south traffic
9. Install metrics and basic observability

### Recommended defaults

1. Container runtime: `containerd`
2. CNI: `Cilium` unless there is a policy reason to use `Calico`
3. Kubernetes install method: `kubeadm`
4. Ingress: `ingress-nginx` only if required

## Phase 4: NVIDIA stack

This phase depends on the exact meaning of `openshell from NVIDIA`.

### Likely common path

If the sandbox needs GPU workloads on Kubernetes, the likely path is:

1. Use Azure GPU VM SKUs
2. Install NVIDIA drivers on GPU nodes
3. Install `NVIDIA Container Toolkit` if required by the node runtime model
4. Install `NVIDIA GPU Operator` in the cluster
5. Validate `nvidia.com/gpu` resource exposure
6. Deploy a test CUDA workload

### Alternative path

If the request really meant `OpenShift`, the plan changes substantially:

1. Do not build plain `kubeadm` Kubernetes first
2. Re-scope around OpenShift install requirements
3. Rework node count, DNS, load balancers, pull secrets, and installation flow

## Phase 5: Sandbox validation

Define clear test criteria before implementation:

1. What sandbox application should run
2. Whether GPU access is required
3. Whether internet egress is allowed
4. What success looks like
5. What logs and metrics should be collected

### Minimum validation

1. Node health is `Ready`
2. CNI is healthy
3. DNS works in-cluster
4. GPU plugin is healthy if GPUs are used
5. Test pod can be scheduled
6. Sandbox workload starts and passes its smoke test

## Suggested delivery order

1. Verify Azure MCP connectivity and authorization
2. Fall back to Azure CLI validation only if MCP is unavailable
3. Write `terraform` for network and VMs
4. Write node bootstrap scripts
5. Write `kubeadm` bootstrap docs or automation
6. Install CNI
7. Install NVIDIA stack
8. Deploy sandbox validation workload
9. Capture troubleshooting notes in runbooks

## Risks

1. GPU quota may not be available in the target Azure region
2. The NVIDIA product is not identified precisely enough yet
3. OpenShift and plain Kubernetes are very different paths
4. Driver and Kubernetes version compatibility can block progress
5. Corporate network restrictions may break image pulls and package installs

## Recommended next implementation step

Before another model starts coding, complete [docs/azure-connectivity-checklist.md](/Users/hwchiu/hwchiu/openqq/docs/azure-connectivity-checklist.md) and fill out every item in [docs/information-needed.md](/Users/hwchiu/hwchiu/openqq/docs/information-needed.md). That will remove the major blockers and allow deterministic infrastructure code generation.
