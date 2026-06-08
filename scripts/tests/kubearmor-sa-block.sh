#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
KUBECONFIG_PATH="$1"
WORK_DIR="$ROOT_DIR/generated/kubearmor-matrix"
mkdir -p "$WORK_DIR"
output="$(WORK_DIR="$WORK_DIR" KUBECONFIG_PATH="$KUBECONFIG_PATH" "$ROOT_DIR/scripts/verify-kubearmor-runtime.sh")"
status="fail"
summary="Service account token read still succeeded"
if grep -Eqi 'permission denied|not permitted|blocked' "$WORK_DIR/verify.stderr"; then
  status="pass"
  summary="KubeArmor blocked service account token access"
fi
jq -n --arg status "$status" --arg summary "$summary" --arg output "$output" '{status:$status,summary:$summary,details:{verifierOutput:$output}}'
