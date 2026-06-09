#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KUBECONFIG_PATH="${KUBECONFIG_PATH:-$ROOT_DIR/generated/stacks/k3s-kubearmor-runc/kubeconfig}"

kubectl --kubeconfig "$KUBECONFIG_PATH" apply -f "$ROOT_DIR/k8s/modelarmor-lab.yaml"
kubectl --kubeconfig "$KUBECONFIG_PATH" -n modelarmor-lab rollout status deploy/modelarmor-demo --timeout=300s
kubectl --kubeconfig "$KUBECONFIG_PATH" apply -f "$ROOT_DIR/k8s/modelarmor-payload-server.yaml"
kubectl --kubeconfig "$KUBECONFIG_PATH" -n modelarmor-lab rollout status deploy/payload-server --timeout=300s
kubectl --kubeconfig "$KUBECONFIG_PATH" apply -f "$ROOT_DIR/k8s/modelarmor-block-sa-token.yaml"
kubectl --kubeconfig "$KUBECONFIG_PATH" apply -f "$ROOT_DIR/k8s/modelarmor-block-shell.yaml"
kubectl --kubeconfig "$KUBECONFIG_PATH" apply -f "$ROOT_DIR/k8s/modelarmor-block-python-egress.yaml"

echo "modelarmor-lab installed on $KUBECONFIG_PATH"
