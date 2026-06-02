# Handoff Notes For Next Model

## What has been done

1. Created planning documents only
2. Identified the main ambiguity around `openshell from NVIDIA`
3. Chose a recommended baseline architecture: Azure VMs + `kubeadm` + `containerd` + CNI + NVIDIA components
4. Elevated Azure connectivity verification to the first execution gate
5. Updated the plan to prefer Azure MCP over Azure CLI when MCP is available
6. Added repo scaffolding for env config, preflight execution, Terraform placeholder layout, and Kubernetes placeholder layout

## What has not been done

1. No Terraform code
2. No Azure provisioning code
3. No Kubernetes manifests
4. No Azure CLI execution
5. No Azure MCP execution
6. No NVIDIA installation steps finalized

## Best next action

Use [docs/azure-connectivity-checklist.md](/Users/hwchiu/hwchiu/openqq/docs/azure-connectivity-checklist.md) first, then use [docs/information-needed.md](/Users/hwchiu/hwchiu/openqq/docs/information-needed.md) as the interview checklist, then generate:

1. `terraform/` for resource group, network, NSGs, and VMs
2. `scripts/` or `ansible/` for OS and Kubernetes bootstrap
3. `k8s/` for CNI, NVIDIA operator, and sandbox manifests
4. `docs/runbooks/` for validation and troubleshooting

## Default assumptions if the user does not specify

1. Azure region with available GPU quota
2. Ubuntu `22.04 LTS`
3. `containerd`
4. `kubeadm`
5. `Cilium`
6. One control plane and two workers for a lab
7. GPU workers only if the sandbox requires them

## Constraint

Do not proceed to implementation until the NVIDIA product and sandbox workload are identified exactly.

## Environment note

In this session, no MCP resources or resource templates were exposed, so Azure MCP could not be verified here. The next model should re-check MCP availability in its own runtime before defaulting to CLI fallback.
