#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KUBECONFIG_PATH="${KUBECONFIG_PATH:-$ROOT_DIR/generated/kubeconfig}"
POD_NAME="${POD_NAME:-$(kubectl --kubeconfig "$KUBECONFIG_PATH" -n default get pod -l app=kubearmor-demo -o jsonpath='{.items[0].metadata.name}')}"
WORK_DIR="${WORK_DIR:-$ROOT_DIR/generated/kubearmor}"
mkdir -p "$WORK_DIR"

set +e
kubectl --kubeconfig "$KUBECONFIG_PATH" -n default exec "$POD_NAME" -- sh -lc 'cat /run/secrets/kubernetes.io/serviceaccount/token' \
  >"$WORK_DIR/verify.stdout" 2>"$WORK_DIR/verify.stderr"
rc=$?
set -e

printf 'stdout:\n'
cat "$WORK_DIR/verify.stdout"
printf '\nstderr:\n'
cat "$WORK_DIR/verify.stderr"

if [[ $rc -eq 0 ]]; then
  echo
  echo "[WARN] service account token read succeeded; KubeArmor block policy did not trigger."
else
  echo
  echo "[INFO] service account token read was blocked."
fi
