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
set +e
kubectl --kubeconfig "$KUBECONFIG_PATH" wait pod/"$POD_NAME" \
  --for=jsonpath='{.status.phase}'=Succeeded --timeout=45s >/dev/null 2>&1
wait_rc=$?
set -e

phase="$(kubectl --kubeconfig "$KUBECONFIG_PATH" get pod "$POD_NAME" -o jsonpath='{.status.phase}' 2>/dev/null || echo Unknown)"
reason="$(kubectl --kubeconfig "$KUBECONFIG_PATH" get pod "$POD_NAME" -o jsonpath='{.status.containerStatuses[0].state.waiting.reason}{.status.containerStatuses[0].state.terminated.reason}' 2>/dev/null || true)"
message="$(kubectl --kubeconfig "$KUBECONFIG_PATH" describe pod "$POD_NAME" 2>/dev/null | tail -n 20)"
logs="$(kubectl --kubeconfig "$KUBECONFIG_PATH" logs "$POD_NAME" 2>/dev/null || true)"

if [[ $wait_rc -eq 0 ]] && grep -qi 'gvisor' <<<"$logs"; then
  jq -n --arg logs "$logs" '{status:"pass",summary:"RuntimeClass gvisor executed inside runsc guest kernel",details:{logs:$logs}}'
elif [[ -n "$logs" && "$logs" == *gvisor* ]]; then
  jq -n --arg phase "$phase" --arg reason "$reason" --arg logs "$logs" '{status:"degraded",summary:"Probe emitted gVisor kernel output but pod did not exit cleanly",details:{phase:$phase,reason:$reason,logs:$logs}}'
else
  jq -n --arg phase "$phase" --arg reason "$reason" --arg describe "$message" '{status:"fail",summary:"RuntimeClass gvisor did not produce a clean probe result",details:{phase:$phase,reason:$reason,describeTail:$describe}}'
fi
