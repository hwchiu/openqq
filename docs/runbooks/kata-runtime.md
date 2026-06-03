# Kata Runtime Runbook

## Goal

Provision the Azure lab so `k3s` can run a third runtime track based on Kata Containers, then attach OpenShell to that runtime for side-by-side comparison against `runc` and `gVisor`.

## Why the VM size changes

Kata needs hardware virtualization on the node. The earlier `Standard_B2s` lab could not work because `/dev/kvm` was missing on both workers.

The Terraform lab therefore switches to:

```hcl
vm_size           = "Standard_D4s_v3"
container_runtime = "kata"
```

This is the conservative path for `eastus`:

1. `Dv3` and newer D-series support nested virtualization
2. `D4s_v3` gives more headroom than `D2s_v3` for `k3s` + OpenShell + Kata overhead
3. Terraform can now recreate the full environment without manual node patching

## Repo assets

1. [scripts/check-kata-prereqs.sh](/Users/hwchiu/hwchiu/openqq/scripts/check-kata-prereqs.sh)
2. [scripts/install-kata.sh](/Users/hwchiu/hwchiu/openqq/scripts/install-kata.sh)
3. [scripts/verify-kata-runtime.sh](/Users/hwchiu/hwchiu/openqq/scripts/verify-kata-runtime.sh)
4. [scripts/install-openshell-sandbox-patcher-kata.sh](/Users/hwchiu/hwchiu/openqq/scripts/install-openshell-sandbox-patcher-kata.sh)
5. [k8s/kata-runtimeclass.yaml](/Users/hwchiu/hwchiu/openqq/k8s/kata-runtimeclass.yaml)
6. [k8s/openshell-sandbox-patcher-kata.yaml](/Users/hwchiu/hwchiu/openqq/k8s/openshell-sandbox-patcher-kata.yaml)

## Workflow

1. `make tf-apply`
2. `./scripts/fetch-kubeconfig.sh`
3. `make kata-prereq`
4. `make kata-verify`
5. `make openshell-install`
6. `make openshell-patcher-kata`
7. Re-run the OpenShell runtime validation flow

## Validation checkpoints

1. Every worker reports `/dev/kvm`
2. `kubectl get runtimeclass kata` succeeds
3. `make kata-verify` produces a successful probe Pod
4. OpenShell sandbox pods can be recreated with `runtimeClassName: kata`
5. OpenShell runtime features can then be compared against the `runc` and `gVisor` tracks
