# Kubernetes Assets

This directory contains Kubernetes manifests and Helm values used by the lab environment.

## Current contents

1. OpenShell Helm values
2. Agent Sandbox validation manifests
3. OpenShell sandbox patcher workaround
4. Sandbox workload examples

## Important note

The current OpenShell Kubernetes path is still experimental. The patcher manifest exists because the current `k3s` + `containerd` runtime path does not automatically produce sandbox pods with the privileges OpenShell needs for network namespace enforcement.
