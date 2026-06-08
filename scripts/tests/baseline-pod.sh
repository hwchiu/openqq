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
kubectl --kubeconfig "$KUBECONFIG_PATH" wait pod/"$POD_NAME" --for=jsonpath='{.status.phase}'=Succeeded --timeout=180s >/dev/null
logs="$(kubectl --kubeconfig "$KUBECONFIG_PATH" logs "$POD_NAME")"
jq -n --arg logs "$logs" '{status:"pass",summary:"Baseline pod completed",details:{logs:$logs}}'
