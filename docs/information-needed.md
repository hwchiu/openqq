# Information Needed

This is the input checklist the next model or engineer should collect before building the actual automation.

## 1. Azure account and access

1. Azure subscription ID
2. Azure tenant ID
3. Whether Azure MCP is available in the execution environment
4. Azure MCP server name or configuration reference if one exists
5. Whether service principal credentials already exist
6. Whether OpenID Connect or managed identity should be used instead of client secret auth
7. Permission scope available to the automation
8. Whether `az login` already works from the operator environment if CLI fallback is needed
9. Whether the target subscription is the default or must be selected explicitly
10. Whether the identity can register or use required resource providers
11. Whether the identity can read quota and SKU availability in the target region

## 2. Deployment target

1. Azure region
2. Environment name such as `dev`, `lab`, or `poc`
3. Naming convention requirements
4. Expected lifetime of the environment
5. Budget cap

## 3. Network

1. VNet CIDR
2. Subnet CIDR or CIDRs
3. Whether public IPs are allowed
4. Allowed source IPs for SSH
5. Whether the Kubernetes API must be publicly reachable
6. DNS requirements
7. Proxy requirements
8. Firewall or NSG restrictions

## 4. VM and OS

1. Control plane node count
2. Worker node count
3. Worker pools if multiple node types are needed
4. VM sizes for control plane
5. VM sizes for workers
6. GPU VM SKU if GPU is required
7. OS image and version
8. Disk size requirements
9. SSH public key

## 5. Kubernetes

1. Kubernetes version target
2. Container runtime preference
3. CNI preference
4. Ingress requirement
5. Storage class requirement
6. Load balancer requirement
7. HA requirement for control plane

## 6. NVIDIA requirements

1. Exact NVIDIA product name to install
2. Whether GPUs are mandatory
3. Required driver version if known
4. Required CUDA version if known
5. Required Helm charts, operators, or manifests
6. Any NVIDIA registry credentials or licenses

## 7. Sandbox workload

1. Exact sandbox application name
2. Container images to deploy
3. CPU, memory, and GPU requirements
4. Required ports
5. Persistent storage requirement
6. External dependencies
7. Smoke test command or success criteria

## 8. Security and compliance

1. Secrets management approach
2. Whether disks must be encrypted with customer-managed keys
3. Whether private registries are required
4. Whether audit logging is required
5. Whether internet egress is restricted

## 9. Operational model

1. Who will run the automation
2. Local execution vs CI pipeline
3. Whether Ansible is acceptable in addition to Terraform
4. How handoff artifacts should be structured
5. Whether the environment is single-use or repeatable

## Blocking ambiguity to resolve

The term `openshell from NVIDIA` must be clarified before implementation. The next model should not guess this.

Possible interpretations:

1. `OpenShift`
2. `NVIDIA GPU Operator`
3. `NVIDIA Container Toolkit`
4. A specific NVIDIA sandbox application
5. A vendor-specific internal tool name
