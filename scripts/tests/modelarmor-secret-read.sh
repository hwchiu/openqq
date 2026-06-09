#!/usr/bin/env bash
set -euo pipefail

KUBECONFIG_PATH="$1"
NS="${MODELARMOR_NAMESPACE:-modelarmor-lab}"
POD="$(kubectl --kubeconfig "$KUBECONFIG_PATH" -n "$NS" get pod -l app=modelarmor-demo -o jsonpath='{.items[0].metadata.name}')"

set +e
kubectl --kubeconfig "$KUBECONFIG_PATH" -n "$NS" exec "$POD" -- python3 -c 'open("/run/secrets/kubernetes.io/serviceaccount/token").read()' \
  >/tmp/modelarmor-secret.stdout 2>/tmp/modelarmor-secret.stderr
rc=$?
set -e

if [[ $rc -ne 0 ]] && grep -Eqi 'permission denied|PermissionError|blocked' /tmp/modelarmor-secret.stderr; then
  jq -n --arg stderr "$(cat /tmp/modelarmor-secret.stderr)" '{status:"pass",summary:"ModelArmor-style lab blocked Python secret read",details:{stderr:$stderr}}'
else
  jq -n --arg stdout "$(cat /tmp/modelarmor-secret.stdout 2>/dev/null || true)" --arg stderr "$(cat /tmp/modelarmor-secret.stderr 2>/dev/null || true)" --argjson rc "$rc" '{status:"fail",summary:"ModelArmor-style lab did not block Python secret read",details:{stdout:$stdout,stderr:$stderr,exitCode:$rc}}'
fi
