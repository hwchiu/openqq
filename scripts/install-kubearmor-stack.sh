#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KUBECONFIG_PATH="${KUBECONFIG_PATH:-$ROOT_DIR/generated/kubeconfig}"
KUBEARMOR_SAMPLE_CONFIG_URL="${KUBEARMOR_SAMPLE_CONFIG_URL:-https://raw.githubusercontent.com/kubearmor/KubeArmor/main/pkg/KubeArmorOperator/config/samples/sample-config.yml}"

command -v helm >/dev/null 2>&1 || { echo "helm is required" >&2; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo "kubectl is required" >&2; exit 1; }

wait_for_namespaced_resource() {
  local kind="$1"
  local name="$2"
  local timeout="${3:-300}"
  local elapsed=0

  until kubectl --kubeconfig "$KUBECONFIG_PATH" -n kubearmor get "$kind" "$name" >/dev/null 2>&1; do
    if (( elapsed >= timeout )); then
      echo "timed out waiting for $kind/$name" >&2
      return 1
    fi
    sleep 5
    elapsed=$((elapsed + 5))
  done
}

helm repo add kubearmor https://kubearmor.github.io/charts >/dev/null 2>&1 || true
helm repo update kubearmor >/dev/null
helm upgrade --install kubearmor-operator kubearmor/kubearmor-operator \
  --kubeconfig "$KUBECONFIG_PATH" \
  -n kubearmor \
  --create-namespace \
  --wait \
  --timeout 10m \
  --set kubearmorOperator.annotateExisting=true

kubectl --kubeconfig "$KUBECONFIG_PATH" apply -f "$KUBEARMOR_SAMPLE_CONFIG_URL"
kubectl --kubeconfig "$KUBECONFIG_PATH" -n kubearmor rollout status deploy/kubearmor-operator --timeout=300s
wait_for_namespaced_resource deploy kubearmor-controller
wait_for_namespaced_resource deploy kubearmor-relay
kubectl --kubeconfig "$KUBECONFIG_PATH" -n kubearmor rollout status deploy/kubearmor-controller --timeout=300s
kubectl --kubeconfig "$KUBECONFIG_PATH" -n kubearmor rollout status deploy/kubearmor-relay --timeout=300s

until kubectl --kubeconfig "$KUBECONFIG_PATH" -n kubearmor get daemonset -l kubearmor-app=kubearmor -o name | grep -q .; do
  sleep 5
done

kubectl --kubeconfig "$KUBECONFIG_PATH" -n kubearmor get daemonset -l kubearmor-app=kubearmor -o name \
  | while read -r ds; do
      kubectl --kubeconfig "$KUBECONFIG_PATH" -n kubearmor rollout status "$ds" --timeout=300s
    done

kubectl --kubeconfig "$KUBECONFIG_PATH" annotate ns default kubearmor-visibility="process,file,network,capabilities" --overwrite
kubectl --kubeconfig "$KUBECONFIG_PATH" apply -f "$ROOT_DIR/k8s/kubearmor-demo-nginx.yaml"
kubectl --kubeconfig "$KUBECONFIG_PATH" rollout status deploy/kubearmor-demo -n default --timeout=300s
kubectl --kubeconfig "$KUBECONFIG_PATH" apply -f "$ROOT_DIR/k8s/kubearmor-audit-etc-nginx.yaml"
kubectl --kubeconfig "$KUBECONFIG_PATH" apply -f "$ROOT_DIR/k8s/kubearmor-block-sa-token.yaml"
