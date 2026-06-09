#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KUBECONFIG_PATH="${KUBECONFIG_PATH:-$ROOT_DIR/generated/stacks/k3s-kubearmor-runc/kubeconfig}"
WORK_DIR="${WORK_DIR:-$ROOT_DIR/generated/modelarmor-lab}"
mkdir -p "$WORK_DIR"

POD="$(kubectl --kubeconfig "$KUBECONFIG_PATH" -n modelarmor-lab get pod -l app=modelarmor-demo -o jsonpath='{.items[0].metadata.name}')"

set +e
kubectl --kubeconfig "$KUBECONFIG_PATH" -n modelarmor-lab exec "$POD" -- python3 -c 'open("/run/secrets/kubernetes.io/serviceaccount/token").read()' \
  >"$WORK_DIR/token.stdout" 2>"$WORK_DIR/token.stderr"
token_rc=$?

kubectl --kubeconfig "$KUBECONFIG_PATH" -n modelarmor-lab exec "$POD" -- python3 -c 'import urllib.request;print(urllib.request.urlopen("http://example.com", timeout=5).status)' \
  >"$WORK_DIR/egress.stdout" 2>"$WORK_DIR/egress.stderr"
egress_rc=$?

kubectl --kubeconfig "$KUBECONFIG_PATH" -n modelarmor-lab exec "$POD" -- cat /proc/1/attr/current \
  >"$WORK_DIR/attr.txt" 2>/dev/null
set -e

cat <<EOF
attr:
$(cat "$WORK_DIR/attr.txt")

token_rc=$token_rc
egress_rc=$egress_rc
EOF
