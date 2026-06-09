#!/usr/bin/env bash
set -euo pipefail

KUBECONFIG_PATH="$1"
NS="${MODELARMOR_NAMESPACE:-modelarmor-lab}"
POD="$(kubectl --kubeconfig "$KUBECONFIG_PATH" -n "$NS" get pod -l app=modelarmor-demo -o jsonpath='{.items[0].metadata.name}')"

set +e
kubectl --kubeconfig "$KUBECONFIG_PATH" -n "$NS" exec "$POD" -- \
  python3 -m pip install colorama==0.4.6 --target /tmp/pip-target \
  >/tmp/modelarmor-pip.stdout 2>/tmp/modelarmor-pip.stderr
rc=$?
set -e

if [[ $rc -eq 0 ]]; then
  jq -n \
    --arg stdout "$(cat /tmp/modelarmor-pip.stdout 2>/dev/null || true)" \
    --arg stderr "$(cat /tmp/modelarmor-pip.stderr 2>/dev/null || true)" \
    '{status:"degraded",summary:"ModelArmor-style lab allowed pip install into /tmp",details:{stdout:$stdout,stderr:$stderr}}'
else
  jq -n \
    --arg stderr "$(cat /tmp/modelarmor-pip.stderr 2>/dev/null || true)" \
    --argjson rc "$rc" \
    '{status:"pass",summary:"ModelArmor-style lab blocked pip install",details:{stderr:$stderr,exitCode:$rc}}'
fi
