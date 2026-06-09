#!/usr/bin/env bash
set -euo pipefail
KUBECONFIG_PATH="$1"
POD_NAME="matrix-smoke-$(date +%s)"
cleanup() {
  kubectl --kubeconfig "$KUBECONFIG_PATH" delete pod "$POD_NAME" --ignore-not-found --wait=false >/dev/null 2>&1 || true
}
trap cleanup EXIT
cat <<YAML | kubectl --kubeconfig "$KUBECONFIG_PATH" apply -f - >/dev/null
apiVersion: v1
kind: Pod
metadata:
  name: ${POD_NAME}
spec:
  restartPolicy: Never
  containers:
    - name: smoke
      image: busybox:stable
      command: ["/bin/sh", "-c", "echo matrix-smoke-ok"]
YAML
if kubectl --kubeconfig "$KUBECONFIG_PATH" wait pod/"$POD_NAME" --for=jsonpath='{.status.phase}'=Succeeded --timeout=180s >/dev/null 2>&1; then
  logs="$(kubectl --kubeconfig "$KUBECONFIG_PATH" logs "$POD_NAME")"
  jq -n --arg logs "$logs" '{status:"pass",summary:"Baseline pod completed",details:{logs:$logs}}'
else
  phase="$(kubectl --kubeconfig "$KUBECONFIG_PATH" get pod "$POD_NAME" -o jsonpath='{.status.phase}' 2>/dev/null || echo Unknown)"
  reason="$(kubectl --kubeconfig "$KUBECONFIG_PATH" get pod "$POD_NAME" -o jsonpath='{.status.containerStatuses[0].state.waiting.reason}' 2>/dev/null || true)"
  message="$(kubectl --kubeconfig "$KUBECONFIG_PATH" describe pod "$POD_NAME" 2>/dev/null | tail -n 40)"
  jq -n \
    --arg phase "${phase:-Unknown}" \
    --arg reason "${reason:-}" \
    --arg message "$message" \
    '{status:"fail",summary:"Baseline pod did not complete",details:{phase:$phase,reason:$reason,describeTail:$message}}'
  exit 1
fi
