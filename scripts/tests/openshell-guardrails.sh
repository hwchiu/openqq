#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
KUBECONFIG_PATH="$1"
STACK_NAME="$2"
SANDBOX_NAME="matrix-${STACK_NAME}-$(date +%s)"
output="$(KUBECONFIG_PATH="$KUBECONFIG_PATH" TERRAFORM_DIR="$ROOT_DIR/terraform/stacks/$STACK_NAME" SANDBOX_NAME="$SANDBOX_NAME" "$ROOT_DIR/scripts/verify-openshell-runtime.sh" 2>&1)"
evidence_dir="$(awk '/evidence written to /{print $4}' <<<"$output" | tail -n1)"
[[ -n "$evidence_dir" && -d "$evidence_dir" ]] || {
  jq -n --arg raw "$output" '{status:"fail",summary:"verify-openshell-runtime did not return an evidence directory",details:{stderr:$raw}}'
  exit 0
}
fs_file="$evidence_dir/filesystem.txt"
post_file="$evidence_dir/curl-post.txt"
get_file="$evidence_dir/curl-get.txt"
logs_file="$evidence_dir/sandbox-logs.txt"
evidence_rel="${evidence_dir#$ROOT_DIR/}"
status="fail"
summary="OpenShell guardrail validation failed"
if grep -q 'policy_denied' "$post_file" && grep -q 'ALLOWED GET' "$logs_file"; then
  if grep -q 'VARTMP_DENIED' "$fs_file"; then
    status="pass"
    summary="L7 and filesystem guardrails both held"
  elif grep -q 'VARTMP_OK' "$fs_file"; then
    status="degraded"
    summary="L7 guardrails held, but filesystem policy degraded"
  fi
fi
jq -n \
  --arg status "$status" \
  --arg summary "$summary" \
  --arg evidence "$evidence_rel" \
  --arg raw "$output" \
  --arg curlGet "$(tr -d '\r' < "$get_file" | head -n1)" \
  '{status:$status,summary:$summary,evidencePath:$evidence,details:{curlGet:$curlGet,verifierOutput:$raw}}'
