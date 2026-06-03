#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KUBECONFIG_PATH="${KUBECONFIG_PATH:-$ROOT_DIR/generated/kubeconfig}"

kubectl --kubeconfig "$KUBECONFIG_PATH" apply -f "$ROOT_DIR/k8s/openshell-sandbox-patcher-kata.yaml"
kubectl --kubeconfig "$KUBECONFIG_PATH" -n openshell rollout status deploy/openshell-sandbox-patcher-kata --timeout=180s
