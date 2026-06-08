#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
KUBECONFIG_PATH="$1"
POD_NAME="gvisor-matrix-$(date +%s)"
cleanup() {
  kubectl --kubeconfig "$KUBECONFIG_PATH" delete pod "$POD_NAME" --ignore-not-found --wait=false >/dev/null 2>&1 || true
}
trap cleanup EXIT
kubectl --kubeconfig "$KUBECONFIG_PATH" get runtimeclass gvisor >/dev/null
cat <<YAML | kubectl --kubeconfig "$KUBECONFIG_PATH" apply -f - >/dev/null
apiVersion: v1
kind: Pod
metadata:
  name: ${POD_NAME}
spec:
  runtimeClassName: gvisor
  restartPolicy: Never
  containers:
    - name: probe
      image: busybox:stable
      command: ["/bin/sh", "-c", "uname -r && echo gvisor-probe-ok"]
YAML
kubectl --kubeconfig "$KUBECONFIG_PATH" wait pod/"$POD_NAME" --for=jsonpath='{.status.phase}'=Succeeded --timeout=180s >/dev/null
logs="$(kubectl --kubeconfig "$KUBECONFIG_PATH" logs "$POD_NAME")"
if grep -qi 'gvisor' <<<"$logs"; then
  jq -n --arg logs "$logs" '{status:"pass",summary:"RuntimeClass gvisor executed inside runsc guest kernel",details:{logs:$logs}}'
else
  jq -n --arg logs "$logs" '{status:"fail",summary:"Probe pod ran but output did not show gVisor guest kernel",details:{logs:$logs}}'
fi
