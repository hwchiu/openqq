# OpenQQ Kata Containers on Azure

This repository now documents one verified path: `K3s 1.34 + CRI-O 1.34 + Kata Containers` on Azure.

The scope is intentionally narrow:

1. how the environment was installed
2. how the environment was verified
3. what tests were actually executed in the Kata environment

## Reading order

1. [Overview](docs/index.html)
2. [Install](docs/install.html)
3. [Verify](docs/verify.html)
4. [Executed tests](docs/tests.html)
5. [Raw evidence](docs/evidence.html)

## Latest verified environment

- Verification date: `2026-06-25`
- Cloud: Azure
- Resource group: `rg-k3s-kata-134`
- Cluster name: `k3s-kata-134`
- Node count: `3`
- VM size: `Standard_D4s_v3`
- OS image: `Ubuntu 22.04.5 LTS`
- Kernel: `6.8.0-1059-azure`
- Kubernetes: `v1.34.1+k3s1`
- Container runtime: `cri-o://1.34.9`
- Kata runtime result: `RuntimeClass kata` passed and the probe pod logged `kata-probe-ok`

## Install

Prepare the shared Azure variables in `terraform/stacks/common.auto.tfvars`:

```hcl
subscription_id = "00000000-0000-0000-0000-000000000000"
tenant_id       = "00000000-0000-0000-0000-000000000000"
admin_username  = "azureuser"
ssh_public_key  = "ssh-ed25519 AAAA..."
```

Then run the one-shot installer:

```bash
cp terraform/stacks/common.auto.tfvars.example terraform/stacks/common.auto.tfvars
cp terraform/stacks/k3s-kata-134/stack.auto.tfvars.example terraform/stacks/k3s-kata-134/stack.auto.tfvars
bash scripts/install-k3s-kata-134.sh
```

The wrapper script performs these steps in order:

1. `terraform apply` for `terraform/stacks/k3s-kata-134`
2. wait until all 3 nodes are `Ready`
3. run `scripts/check-kata-prereqs.sh`
4. run `scripts/install-kata.sh`
5. run `scripts/verify-kata-runtime.sh`

The verified stack defaults are:

- `K3s v1.34.1+k3s1`
- `CRI-O v1.34`
- `Standard_D4s_v3`
- `Ubuntu 22.04 LTS`
- `KATA_VERSION=3.31.0` inside `scripts/install-kata.sh`

## Verify

Re-run the verification steps with:

```bash
KUBECONFIG_PATH=generated/stacks/k3s-kata-134/kubeconfig \
TF_DIR=terraform/stacks/k3s-kata-134 \
bash scripts/check-kata-prereqs.sh

KUBECONFIG_PATH=generated/stacks/k3s-kata-134/kubeconfig \
bash scripts/verify-kata-runtime.sh
```

What to expect:

- all 3 nodes show `Ready`
- each node exposes `/dev/kvm`
- `kubectl get runtimeclass kata` succeeds
- the verify pod reaches `Succeeded`
- pod logs include a guest kernel line and `kata-probe-ok`

## Tests executed in the Kata environment

| Test | Status | Evidence |
| --- | --- | --- |
| 3-node Azure cluster bootstrap | PASS | [nodes-wide.txt](records/raw/2026-06-25/k3s-kata-134-runtime-verify/nodes-wide.txt) |
| Kubernetes and cluster-info capture | PASS | [versions.txt](records/raw/2026-06-25/k3s-kata-134-runtime-verify/versions.txt) |
| `/dev/kvm` prerequisite on all nodes | PASS | [prereqs.txt](records/raw/2026-06-25/k3s-kata-134-runtime-verify/prereqs.txt) |
| CRI-O Kata drop-ins present on all nodes | PASS | [crio-kata-dropins.txt](records/raw/2026-06-25/k3s-kata-134-runtime-verify/crio-kata-dropins.txt) |
| `RuntimeClass kata` object present | PASS | [runtimeclass-kata.yaml](records/raw/2026-06-25/k3s-kata-134-runtime-verify/runtimeclass-kata.yaml) |
| Kata probe pod completed | PASS | [kata-evidence-pod.yaml](records/raw/2026-06-25/k3s-kata-134-runtime-verify/kata-evidence-pod.yaml) |
| Kata probe log contains `kata-probe-ok` | PASS | [kata-evidence-logs.txt](records/raw/2026-06-25/k3s-kata-134-runtime-verify/kata-evidence-logs.txt) |
| Service mesh scenarios | NOT TESTED YET | Not run in this environment |
| Filesystem guardrail scenarios | NOT TESTED YET | Not run in this environment |
| Network guardrail scenarios | NOT TESTED YET | Not run in this environment |
| Privilege surface scenarios | NOT TESTED YET | Not run in this environment |
| Agentic AI scenarios | NOT TESTED YET | Not run in this environment |

## Raw evidence

All stored evidence for the latest Kata verification lives under:

- `records/raw/2026-06-25/k3s-kata-134-runtime-verify/`

The GitHub Pages reader is intentionally limited to Kata installation, verification, and executed tests. It does not include cross-solution comparison pages.
