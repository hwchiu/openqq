# CRI-O Family Cilium Baseline Design

Date: 2026-06-10
Status: Approved in conversation and entering implementation

## Goal

Redefine every `CRI-O family` candidate in this repository to use `Cilium` as the formal Kubernetes CNI baseline instead of `Flannel`.

This applies to:

1. `k8s + cri-o`
2. `k8s + OpenShell + cri-o`
3. `k8s + cri-o + KubeArmor`

The purpose is to stop treating the current `Flannel`-based CRI-O wiring as the official comparison baseline, because it has already distorted the decision record and created repeated CNI-specific failures that should no longer anchor the evaluation model.

## Problem Statement

The current CRI-O-based stacks are bootstrapped by:

- installing `CRI-O`
- starting `K3s`
- pinning a custom `Flannel` CNI conflist
- manually wiring CRI-O CNI binaries and paths

That design has several problems:

1. It couples the formal candidate result to `Flannel`-specific behavior.
2. It requires special repair logic around `Flannel` CNI config.
3. It has already produced repeated `bandwidth` plugin panics that dominate the outcome.
4. It does not represent the intended future comparison baseline for CRI-O-based candidates.

The repository should therefore move to a new rule:

`CRI-O family candidates are compared on top of Cilium, not Flannel.`

## Design Decision

All CRI-O family stacks will move to:

- `K3s` with no built-in flannel CNI
- `CRI-O` as the container runtime
- `Cilium` installed after cluster bootstrap

This means the baseline becomes:

- `K3s + CRI-O + Cilium`

and then solution-specific layers are added on top:

- `plain CRI-O`
- `OpenShell + CRI-O`
- `KubeArmor + CRI-O`

## New Bootstrap Model

### Platform bootstrap

For CRI-O family stacks:

1. Terraform creates Azure infrastructure.
2. Cloud-init installs `CRI-O`.
3. `K3s` is installed with flannel disabled.
4. Nodes register and become ready.
5. `Cilium` is installed as the cluster CNI.
6. `Cilium` readiness is verified.

Only after that does candidate-specific installation begin.

### Candidate-specific bootstrap

After `Cilium` is ready:

- `plain CRI-O` proceeds directly to baseline smoke tests
- `OpenShell + CRI-O` installs agent-sandbox controller and OpenShell components
- `KubeArmor + CRI-O` installs KubeArmor and then scenario-specific explicit policies

## Failure Classification Under The New Model

The repository must now distinguish three different failure layers for CRI-O family stacks:

1. `cluster bootstrap failure`
2. `cilium readiness failure`
3. `solution bootstrap failure`

This is important because a failure before Cilium is ready should not be misreported as an OpenShell or KubeArmor failure.

## Scope Of Code Changes

### Terraform / cloud-init

The current CRI-O cloud-init templates must stop writing and referencing:

- `/etc/rancher/k3s/10-flannel.conflist`
- `--flannel-cni-conf`
- flannel-specific repair assumptions

Instead they should:

- keep CRI-O installation
- keep CNI binary path preparation
- install `K3s` with flannel disabled
- leave the cluster ready for a later `Cilium` install step

### Install scripts

The CRI-O family install scripts must be reordered so they:

1. apply Terraform
2. fetch kubeconfig
3. wait for nodes
4. install `Cilium`
5. verify `Cilium`
6. continue to candidate-specific installation

### Shared helper scripts

A new shared install helper should encapsulate:

- Helm repo setup for Cilium
- installation values
- wait logic for `cilium` DaemonSet / operator
- a small smoke check for CNI health

This should be reusable across all CRI-O family stacks.

### Regression tests

Current regression tests that assert pinned flannel config are now wrong for the official model.

They must be replaced by tests that assert:

- flannel-specific config is absent from CRI-O templates
- CRI-O stacks disable built-in flannel
- Cilium install steps are present in CRI-O family workflows

## Documentation Changes

The official reading model must change in `current-state` and Pages:

- `Flannel`-based CRI-O findings become historical evidence
- `Cilium` becomes the formal CRI-O family baseline
- any future recommendation text must explicitly say CRI-O family results are now being re-established on Cilium

Old reports are not deleted, but they are no longer the primary basis for recommendation.

## Verification Requirements

Implementation is not complete until at least the following are true:

1. CRI-O cloud-init templates no longer pin flannel config.
2. A shared `Cilium` install flow exists and is used by every CRI-O family install script.
3. Regression tests reflect the new baseline assumption.
4. `current-state` and reports explain the baseline switch clearly.

## Non-Goals

This change does not yet require:

- migrating non-CRI-O candidates to Cilium
- redesigning the full GitHub Pages information architecture
- completing every scenario family for every candidate in the same commit

Those remain follow-on work.
