#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KUBECONFIG_PATH="${KUBECONFIG_PATH:-$ROOT_DIR/generated/kubeconfig}"
POD_NAME="kata-verify-$(date +%s)"

cat <<YAML | kubectl --kubeconfig "$KUBECONFIG_PATH" apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: ${POD_NAME}
spec:
  runtimeClassName: kata
  restartPolicy: Never
  containers:
    - name: probe
      image: alpine:3.22
      command: ["/bin/sh", "-lc", "uname -a && cat /proc/version && echo kata-probe-ok"]
YAML

cleanup() {
  kubectl --kubeconfig "$KUBECONFIG_PATH" delete pod "$POD_NAME" --ignore-not-found >/dev/null 2>&1 || true
}
trap cleanup EXIT

kubectl --kubeconfig "$KUBECONFIG_PATH" wait --for=jsonpath='{.status.phase}'=Succeeded pod/"$POD_NAME" --timeout=300s

echo "=== RuntimeClass ==="
kubectl --kubeconfig "$KUBECONFIG_PATH" get runtimeclass kata

echo "=== Pod Spec ==="
kubectl --kubeconfig "$KUBECONFIG_PATH" get pod "$POD_NAME" -o yaml | sed -n '1,120p'

echo "=== Pod Logs ==="
kubectl --kubeconfig "$KUBECONFIG_PATH" logs "$POD_NAME"
