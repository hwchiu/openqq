#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KUBECONFIG_PATH="${KUBECONFIG_PATH:-$ROOT_DIR/generated/kubeconfig}"
AGENT_SANDBOX_MANIFEST_URL="${AGENT_SANDBOX_MANIFEST_URL:-https://github.com/kubernetes-sigs/agent-sandbox/releases/latest/download/manifest.yaml}"
OPENSHELL_CHART_VERSION="${OPENSHELL_CHART_VERSION:-0.0.53}"

kubectl --kubeconfig "$KUBECONFIG_PATH" apply -f "$AGENT_SANDBOX_MANIFEST_URL"
kubectl --kubeconfig "$KUBECONFIG_PATH" -n agent-sandbox-system rollout status deploy/agent-sandbox-controller --timeout=300s

helm upgrade --install openshell oci://ghcr.io/nvidia/openshell/helm-chart \
  --kubeconfig "$KUBECONFIG_PATH" \
  --version "$OPENSHELL_CHART_VERSION" \
  --namespace openshell \
  --create-namespace \
  -f "$ROOT_DIR/k8s/openshell-values.yaml"

kubectl --kubeconfig "$KUBECONFIG_PATH" -n openshell rollout status statefulset/openshell --timeout=300s

"$ROOT_DIR/scripts/install-openshell-sandbox-patcher.sh"
