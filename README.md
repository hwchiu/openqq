# OpenShell Runtime Lab on Azure

This repository now contains repeatable Azure lab assets for four independent Kubernetes security environments:

1. `k3s + gVisor`
2. `k3s + OpenShell + runc`
3. `k3s + OpenShell + gVisor`
4. `k3s + KubeArmor + runc`

## Fast entry points

1. Site index: [docs/index.html](/Users/hwchiu/hwchiu/openqq/docs/index.html)
2. Install catalog: [docs/installs.html](/Users/hwchiu/hwchiu/openqq/docs/installs.html)
3. Comparison matrix runbook: [docs/runbooks/install-comparison-matrix.md](/Users/hwchiu/hwchiu/openqq/docs/runbooks/install-comparison-matrix.md)
4. Comparison matrix page: [docs/matrix.html](/Users/hwchiu/hwchiu/openqq/docs/matrix.html)
5. Terraform stacks: `terraform/stacks/`
6. One-shot installer: [scripts/install-comparison-matrix.sh](/Users/hwchiu/hwchiu/openqq/scripts/install-comparison-matrix.sh)
7. One-shot test runner: [scripts/run-comparison-matrix-tests.sh](/Users/hwchiu/hwchiu/openqq/scripts/run-comparison-matrix-tests.sh)
8. One-shot destroy: [scripts/destroy-comparison-matrix.sh](/Users/hwchiu/hwchiu/openqq/scripts/destroy-comparison-matrix.sh)

## Install paths

1. [docs/runbooks/install-k3s-gvisor.md](/Users/hwchiu/hwchiu/openqq/docs/runbooks/install-k3s-gvisor.md)
2. [docs/runbooks/install-k3s-openshell-runc.md](/Users/hwchiu/hwchiu/openqq/docs/runbooks/install-k3s-openshell-runc.md)
3. [docs/runbooks/install-k3s-openshell-gvisor.md](/Users/hwchiu/hwchiu/openqq/docs/runbooks/install-k3s-openshell-gvisor.md)
4. [docs/runbooks/install-k3s-kubearmor-runc.md](/Users/hwchiu/hwchiu/openqq/docs/runbooks/install-k3s-kubearmor-runc.md)
5. [docs/runbooks/comparison-matrix-tests.md](/Users/hwchiu/hwchiu/openqq/docs/runbooks/comparison-matrix-tests.md)

## Shared Azure inputs

Provide shared Azure values in one of these ways:

1. `terraform/stacks/common.auto.tfvars`
2. Environment variables such as `AZURE_SUBSCRIPTION_ID`, `AZURE_TENANT_ID`, and `AZURE_SSH_PUBLIC_KEY_PATH`
3. Existing `terraform/terraform.tfvars`

## Notes

- Each stack has its own Terraform root and state file.
- Each stack writes kubeconfig under `generated/stacks/<stack-name>/kubeconfig`.
- The matrix installer creates the four environments serially through one command so they can coexist safely.
- The matrix test runner writes publishable results to `docs/data/comparison-matrix.json`.
