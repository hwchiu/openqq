# Kubernetes Scaffold

This directory is reserved for Kubernetes manifests and Helm values.

## Expected contents in the next implementation pass

1. CNI installation assets
2. NVIDIA operator or driver-related manifests
3. Sandbox namespace and workload manifests
4. Validation workloads

## Constraint

Do not finalize manifests until these are known:

1. Exact Kubernetes version
2. CNI choice
3. Exact NVIDIA product
4. Sandbox workload definition

