# OpenShell Kubernetes Compatibility

This note captures the Kubernetes-side requirements for running NVIDIA OpenShell based on the upstream repository.

## Source summary

OpenShell's Kubernetes deployment path is experimental and depends on the Kubernetes Agent Sandbox controller and CRDs.

## Hard requirements

1. A working Kubernetes cluster
2. Helm access to `oci://ghcr.io/nvidia/openshell/helm-chart`
3. The `agent-sandbox` CRDs and controller installed before OpenShell
4. Reachability from CLI clients to the OpenShell gateway

## Upstream requirements that affect our cluster design

### 1. OpenShell on Kubernetes is experimental

The upstream repo explicitly marks the Kubernetes deployment path as experimental.

### 2. `agent-sandbox` is mandatory

Before installing the OpenShell Helm chart, the cluster must have:

```bash
kubectl apply -f https://github.com/kubernetes-sigs/agent-sandbox/releases/latest/download/manifest.yaml
```

Without that controller and those CRDs, OpenShell cannot manage sandboxes on Kubernetes.

### 3. Remote clusters need an externally reachable gateway address

The Helm chart defaults are local-cluster oriented. For a remote Azure cluster, `sshGatewayHost` and `sshGatewayPort` must be set to an address reachable from this session.

This is required because the chart defaults assume `127.0.0.1:8080` for local development.

### 4. Optional user namespaces require a modern Kubernetes/runtime stack

The chart exposes `enableUserNamespaces`. Upstream notes that this requires:

1. Kubernetes `1.33+`
2. Runtime support
3. Linux `5.12+`

Our current target stack is recent enough on the Kubernetes version side, but runtime support still needs validation before enabling it.

### 5. Gateway API is optional, not mandatory

The chart includes optional `grpcRoute` support. If used, the cluster also needs a Gateway API controller such as Envoy Gateway.

This is not required for a minimal first deployment.

### 6. GPU support is optional and not satisfied by the current cluster design

OpenShell upstream marks GPU support as experimental and requires NVIDIA drivers plus the NVIDIA Container Toolkit on the host.

Our current Azure cluster design uses standard CPU VMs, so it supports the non-GPU OpenShell path only.

If GPU-backed sandboxes are required later, we need:

1. GPU-capable Azure worker nodes
2. NVIDIA drivers
3. NVIDIA Container Toolkit
4. Possibly runtime-class and isolation tuning depending on the sandbox model

## What our cluster must support

For the first successful OpenShell deployment, the cluster should provide:

1. Three healthy nodes
2. Working in-cluster networking
3. Pull access to GHCR images
4. Helm
5. `agent-sandbox` CRDs and controller
6. A stable external endpoint for the OpenShell gateway

## Fit of the current implementation choice

### `k3s`

`k3s` is acceptable for the first OpenShell test deployment because:

1. OpenShell requires Kubernetes plus `agent-sandbox`, not specifically `kubeadm`
2. The chart requirement is about cluster capabilities, not the bootstrap tool
3. `k3s` gives us a fast path to a working cluster for validating the Helm deployment

### Current caveat

The cluster still must be validated against:

1. `agent-sandbox` installation
2. External gateway exposure
3. Non-GPU first deployment

## Recommended deployment order

1. Finish bringing up the corrected 3-node cluster
2. Install `agent-sandbox`
3. Install OpenShell with explicit remote-cluster values for gateway exposure
4. Verify `openshell` CLI connectivity from this session
5. Add GPU support only if the workload actually needs it
