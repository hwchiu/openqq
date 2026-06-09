#!/usr/bin/env bash
set -euo pipefail

KUBECONFIG_PATH="$1"
NS="${MODELARMOR_NAMESPACE:-modelarmor-lab}"
POD="$(kubectl --kubeconfig "$KUBECONFIG_PATH" -n "$NS" get pod -l app=modelarmor-demo -o jsonpath='{.items[0].metadata.name}')"

set +e
kubectl --kubeconfig "$KUBECONFIG_PATH" -n "$NS" exec "$POD" -- python3 -c 'import urllib.request;print(urllib.request.urlopen("http://example.com", timeout=5).status)' \
  >/tmp/modelarmor-egress.stdout 2>/tmp/modelarmor-egress.stderr
rc=$?
set -e

if [[ $rc -ne 0 ]]; then
  jq -n --arg stderr "$(cat /tmp/modelarmor-egress.stderr 2>/dev/null || true)" '{status:"pass",summary:"ModelArmor-style lab blocked Python HTTP egress",details:{stderr:$stderr}}'
else
  jq -n --arg stdout "$(cat /tmp/modelarmor-egress.stdout 2>/dev/null || true)" --arg stderr "$(cat /tmp/modelarmor-egress.stderr 2>/dev/null || true)" '{status:"fail",summary:"ModelArmor-style lab allowed Python HTTP egress",details:{stdout:$stdout,stderr:$stderr}}'
fi
