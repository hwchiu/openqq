#!/usr/bin/env bash
set -euo pipefail

KUBECONFIG_PATH="$1"
NS="${MODELARMOR_NAMESPACE:-modelarmor-lab}"
POD="$(kubectl --kubeconfig "$KUBECONFIG_PATH" -n "$NS" get pod -l app=modelarmor-demo -o jsonpath='{.items[0].metadata.name}')"

set +e
kubectl --kubeconfig "$KUBECONFIG_PATH" -n "$NS" exec "$POD" -- python3 -c 'import subprocess; subprocess.run(["/bin/sh","-c","echo escaped"], check=True)' \
  >/tmp/modelarmor-shell.stdout 2>/tmp/modelarmor-shell.stderr
rc=$?
set -e

if [[ $rc -ne 0 ]] && grep -Eqi 'permission denied|PermissionError|Operation not permitted|not permitted|blocked' /tmp/modelarmor-shell.stderr; then
  jq -n --arg stderr "$(cat /tmp/modelarmor-shell.stderr)" '{status:"pass",summary:"ModelArmor-style lab blocked Python subprocess shell escape",details:{stderr:$stderr}}'
else
  jq -n --arg stdout "$(cat /tmp/modelarmor-shell.stdout 2>/dev/null || true)" --arg stderr "$(cat /tmp/modelarmor-shell.stderr 2>/dev/null || true)" --argjson rc "$rc" '{status:"fail",summary:"ModelArmor-style lab did not block Python subprocess shell escape",details:{stdout:$stdout,stderr:$stderr,exitCode:$rc}}'
fi
