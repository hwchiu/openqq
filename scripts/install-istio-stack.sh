#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STACK_NAME="${1:-}"
KUBECONFIG_PATH="${2:-}"
ISTIO_NAMESPACE="${ISTIO_NAMESPACE:-istio-system}"

if [[ -z "$STACK_NAME" || -z "$KUBECONFIG_PATH" ]]; then
  echo "usage: $0 <stack-name> <kubeconfig-path>" >&2
  exit 1
fi

command -v helm >/dev/null 2>&1 || { echo "helm is required" >&2; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo "kubectl is required" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 1; }

helm repo add istio https://istio-release.storage.googleapis.com/charts >/dev/null 2>&1 || true
helm repo update istio >/dev/null

ISTIO_CHART_VERSION="${ISTIO_CHART_VERSION:-$(helm search repo istio/base --versions -o json | jq -r '.[0].version')}"

helm upgrade --install istio-base istio/base \
  --kubeconfig "$KUBECONFIG_PATH" \
  --namespace "$ISTIO_NAMESPACE" \
  --create-namespace \
  --version "$ISTIO_CHART_VERSION" \
  --set defaultRevision=default \
  --wait

helm upgrade --install istiod istio/istiod \
  --kubeconfig "$KUBECONFIG_PATH" \
  --namespace "$ISTIO_NAMESPACE" \
  --version "$ISTIO_CHART_VERSION" \
  --wait

kubectl --kubeconfig "$KUBECONFIG_PATH" -n "$ISTIO_NAMESPACE" rollout status deploy/istiod --timeout=300s

echo "$ISTIO_CHART_VERSION"
