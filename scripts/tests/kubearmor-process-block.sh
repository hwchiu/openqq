#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
KUBECONFIG_PATH="$1"
MANIFEST="$ROOT_DIR/k8s/kubearmor-block-sleep.yaml"
WORK_DIR="$ROOT_DIR/generated/kubearmor-process"
mkdir -p "$WORK_DIR"

cleanup() {
  kubectl --kubeconfig "$KUBECONFIG_PATH" delete -f "$MANIFEST" --ignore-not-found >/dev/null 2>&1 || true
}
trap cleanup EXIT

kubectl --kubeconfig "$KUBECONFIG_PATH" apply -f "$MANIFEST" >/dev/null
sleep 5

set +e
kubectl --kubeconfig "$KUBECONFIG_PATH" -n default exec deploy/kubearmor-demo -- /usr/bin/sleep 1 \
  >"$WORK_DIR/verify.stdout" 2>"$WORK_DIR/verify.stderr"
rc=$?
set -e

if [[ $rc -ne 0 ]] && grep -Eqi 'permission denied|not permitted|blocked' "$WORK_DIR/verify.stderr"; then
  jq -n '{status:"pass",summary:"KubeArmor blocked /usr/bin/sleep execution",details:{stderr:$stderr}}' --arg stderr "$(cat "$WORK_DIR/verify.stderr")"
else
  jq -n '{status:"fail",summary:"KubeArmor did not block /usr/bin/sleep execution",details:{stdout:$stdout,stderr:$stderr,exitCode:$rc}}' \
    --arg stdout "$(cat "$WORK_DIR/verify.stdout")" \
    --arg stderr "$(cat "$WORK_DIR/verify.stderr")" \
    --argjson rc "$rc"
fi
