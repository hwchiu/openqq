# OpenShell Runbook

## Installed components

1. `agent-sandbox` controller and CRD
2. `openshell` Helm release in namespace `openshell`

## Files

1. [k8s/openshell-values.yaml](/Users/hwchiu/hwchiu/openqq/k8s/openshell-values.yaml)
2. [terraform/main.tf](/Users/hwchiu/hwchiu/openqq/terraform/main.tf)
3. [k8s/openshell-sandbox-patcher.yaml](/Users/hwchiu/hwchiu/openqq/k8s/openshell-sandbox-patcher.yaml)
4. [scripts/install-openshell-stack.sh](/Users/hwchiu/hwchiu/openqq/scripts/install-openshell-stack.sh)
5. [scripts/verify-openshell-runtime.sh](/Users/hwchiu/hwchiu/openqq/scripts/verify-openshell-runtime.sh)

## Current lab configuration

1. `service.type=LoadBalancer`
2. `server.disableTls=true`
3. `server.auth.allowUnauthenticatedUsers=true`
4. Terraform NSG allows NodePort range `30000-32767`

## Why NodePort access works

`k3s` service load balancer exposes the service through node public IPs and a NodePort.

The current OpenShell gateway NodePort is `30968`.

## Verified reachable endpoints

1. `http://138.91.122.32:30968`
2. `http://172.191.110.55:30968`
3. `http://4.157.250.220:30968`

An HTTP `404` from `/` is expected here and confirms the gateway is reachable over the network.

## Security note

This is a lab-first configuration only. It intentionally disables TLS and allows unauthenticated users to simplify initial validation.

Do not treat this as a production configuration.

## Sandbox patcher

Current `k3s` + `containerd` validation requires one Kubernetes-side workaround: OpenShell sandbox pods need `privileged: true` so the supervisor can create its network namespace and proxy path.

This repo now carries [k8s/openshell-sandbox-patcher.yaml](/Users/hwchiu/hwchiu/openqq/k8s/openshell-sandbox-patcher.yaml), which:

1. Watches OpenShell-managed `Sandbox` CRs in the `openshell` namespace
2. Patches `spec.podTemplate.spec.containers[0].securityContext.privileged=true`
3. Deletes a stale non-privileged Pod so the controller recreates it from the patched spec

This is a reproducibility workaround, not a final upstream-quality integration.
