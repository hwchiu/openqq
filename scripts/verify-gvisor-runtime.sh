#!/usr/bin/env bash
# Verifies gVisor (runsc) RuntimeClass is functional by running a probe pod.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KUBECONFIG_PATH="${KUBECONFIG_PATH:-$ROOT_DIR/generated/kubeconfig}"

POD_NAME="gvisor-verify-$(date +%s)"

cleanup() {
  kubectl --kubeconfig "$KUBECONFIG_PATH" delete pod "$POD_NAME" --ignore-not-found --wait=false >/dev/null 2>&1 || true
}
trap cleanup EXIT

cat <<EOF | kubectl --kubeconfig "$KUBECONFIG_PATH" apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: ${POD_NAME}
  namespace: default
spec:
  runtimeClassName: gvisor
  restartPolicy: Never
  containers:
    - name: probe
      image: busybox:stable
      command: ["/bin/sh", "-c", "uname -r && cat /proc/version && echo gVisor-probe-OK"]
EOF

kubectl --kubeconfig "$KUBECONFIG_PATH" wait pod/"$POD_NAME" \
  --for=condition=Ready --timeout=120s 2>/dev/null || \
kubectl --kubeconfig "$KUBECONFIG_PATH" wait pod/"$POD_NAME" \
  --for=jsonpath='{.status.phase}'=Succeeded --timeout=120s

echo ""
echo "=== Pod logs ==="
kubectl --kubeconfig "$KUBECONFIG_PATH" logs "$POD_NAME"

echo ""
echo "=== RuntimeClass ==="
kubectl --kubeconfig "$KUBECONFIG_PATH" get runtimeclass gvisor

echo ""
echo "gVisor verify: PASSED"
