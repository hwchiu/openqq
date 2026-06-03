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
9. Runtime selection between embedded `containerd`, `gVisor`, `Kata Containers`, and external `CRI-O`

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

## Runtime selection

The stack supports:

1. `containerd`
2. `crio`
3. `gvisor`
4. `kata`

Set `container_runtime` in `terraform.tfvars`:

```hcl
container_runtime = "containerd"
```

or:

```hcl
container_runtime = "crio"
crio_version      = "v1.35"
```

or:

```hcl
container_runtime = "gvisor"
```

or:

```hcl
container_runtime = "kata"
vm_size           = "Standard_D4s_v3"
```

When `container_runtime="crio"`, cloud-init installs CRI-O from the official packaging repository, enables the `crio` service, points K3s at `unix:///var/run/crio/crio.sock`, and shares the K3s CNI config directory with CRI-O.

When `container_runtime="gvisor"`, cloud-init installs `runsc` and writes a K3s `config-v3.toml.tmpl` that exposes the `runsc` runtime through `RuntimeClass/gvisor`.

When `container_runtime="kata"`, cloud-init installs the official Kata static release, writes a K3s `config-v3.toml.tmpl` that exposes `io.containerd.kata.v2`, and expects Azure VM sizes with nested virtualization support. `Standard_B2s` is not sufficient because it does not expose `/dev/kvm`. The lab defaults to `Standard_D4s_v3` because `eastus` capacity for `D4s_v5` was not stable enough during rebuild.

## Design note

The Azure node network CIDR is intentionally separated from the `k3s` pod and service CIDRs. This avoids the overlap bug that broke the earlier shell-driven cluster build.
