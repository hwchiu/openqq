#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KUBECONFIG_PATH="${KUBECONFIG_PATH:-$ROOT_DIR/generated/kubeconfig}"
KUBEARMOR_SAMPLE_CONFIG_URL="${KUBEARMOR_SAMPLE_CONFIG_URL:-https://raw.githubusercontent.com/kubearmor/KubeArmor/main/pkg/KubeArmorOperator/config/samples/sample-config.yml}"

command -v helm >/dev/null 2>&1 || { echo "helm is required" >&2; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo "kubectl is required" >&2; exit 1; }

helm repo add kubearmor https://kubearmor.github.io/charts >/dev/null 2>&1 || true
helm repo update kubearmor >/dev/null
helm upgrade --install kubearmor-operator kubearmor/kubearmor-operator \
  --kubeconfig "$KUBECONFIG_PATH" \
  -n kubearmor \
  --create-namespace

kubectl --kubeconfig "$KUBECONFIG_PATH" apply -f "$KUBEARMOR_SAMPLE_CONFIG_URL"
kubectl --kubeconfig "$KUBECONFIG_PATH" annotate ns default kubearmor-visibility="process,file,network" --overwrite
kubectl --kubeconfig "$KUBECONFIG_PATH" apply -f "$ROOT_DIR/k8s/kubearmor-demo-nginx.yaml"
kubectl --kubeconfig "$KUBECONFIG_PATH" rollout status deploy/kubearmor-demo -n default --timeout=300s
kubectl --kubeconfig "$KUBECONFIG_PATH" apply -f "$ROOT_DIR/k8s/kubearmor-audit-etc-nginx.yaml"
kubectl --kubeconfig "$KUBECONFIG_PATH" apply -f "$ROOT_DIR/k8s/kubearmor-block-sa-token.yaml"
