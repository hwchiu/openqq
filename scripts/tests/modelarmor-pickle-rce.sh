#!/usr/bin/env bash
set -euo pipefail

KUBECONFIG_PATH="$1"
NS="${MODELARMOR_NAMESPACE:-modelarmor-lab}"
POD="$(kubectl --kubeconfig "$KUBECONFIG_PATH" -n "$NS" get pod -l app=modelarmor-demo -o jsonpath='{.items[0].metadata.name}')"

set +e
kubectl --kubeconfig "$KUBECONFIG_PATH" -n "$NS" exec "$POD" -- \
  python3 -c 'import os,pickle,pathlib; R=type("R",(),{"__reduce__":lambda self:(os.system,("echo pickle-rce >/tmp/pickle-proof",))}); payload=pickle.dumps(R()); print(len(payload)); print(pickle.loads(payload)); print(pathlib.Path("/tmp/pickle-proof").read_text().strip())' \
  >/tmp/modelarmor-pickle.stdout 2>/tmp/modelarmor-pickle.stderr
rc=$?
set -e

if [[ $rc -eq 0 ]]; then
  jq -n \
    --arg stdout "$(cat /tmp/modelarmor-pickle.stdout 2>/dev/null || true)" \
    --arg stderr "$(cat /tmp/modelarmor-pickle.stderr 2>/dev/null || true)" \
    '{status:"fail",summary:"ModelArmor-style lab allowed pickle-driven code execution",details:{stdout:$stdout,stderr:$stderr}}'
else
  jq -n \
    --arg stderr "$(cat /tmp/modelarmor-pickle.stderr 2>/dev/null || true)" \
    --argjson rc "$rc" \
    '{status:"pass",summary:"ModelArmor-style lab blocked pickle-driven code execution",details:{stderr:$stderr,exitCode:$rc}}'
fi
