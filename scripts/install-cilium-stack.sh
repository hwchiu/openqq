#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib-stack.sh
source "$ROOT_DIR/scripts/lib-stack.sh"

KUBECONFIG_PATH="${KUBECONFIG_PATH:?KUBECONFIG_PATH is required}"
RELEASE_NAME="${RELEASE_NAME:-cilium}"
NAMESPACE="${NAMESPACE:-kube-system}"

require_bin helm
require_bin kubectl

helm repo add cilium https://helm.cilium.io >/dev/null 2>&1 || true
helm repo update cilium >/dev/null

helm upgrade --install "$RELEASE_NAME" cilium/cilium \
  --kubeconfig "$KUBECONFIG_PATH" \
  --namespace "$NAMESPACE" \
  --create-namespace \
  --wait \
  --timeout 10m \
  --set kubeProxyReplacement=false \
  --set operator.replicas=1

kubectl --kubeconfig "$KUBECONFIG_PATH" -n "$NAMESPACE" rollout status ds/cilium --timeout=600s
kubectl --kubeconfig "$KUBECONFIG_PATH" -n "$NAMESPACE" rollout status deploy/cilium-operator --timeout=600s
