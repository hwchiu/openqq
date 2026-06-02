# K3s Cluster Runbook

## Scope

This runbook provisions a three-node Azure-backed Kubernetes cluster:

1. `cp-0`
2. `worker-1`
3. `worker-2`

The current implementation uses `k3s` because it is the fastest path to a working cluster that can be accessed directly from this session.

## Commands

Create the cluster:

```bash
make cluster-up
```

Fetch kubeconfig again later:

```bash
make cluster-kubeconfig
```

Check cluster status:

```bash
make cluster-status
```

Delete the cluster:

```bash
make cluster-down
```

## Generated artifacts

1. `generated/cluster.env`
2. `generated/kubeconfig`
3. `generated/kubeconfig.raw`

## Current limitation

The NVIDIA `openshell` layer is still blocked on exact product identification. The base Kubernetes cluster can be created now, but the NVIDIA layer should not be guessed.
