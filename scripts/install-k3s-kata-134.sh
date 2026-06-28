#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STACK_NAME="k3s-kata-134"
# shellcheck source=scripts/lib-stack.sh
source "$ROOT_DIR/scripts/lib-stack.sh"
require_bin jq

TF_VAR_k3s_version="${TF_VAR_k3s_version:-v1.34.1+k3s1}" \
TF_VAR_crio_version="${TF_VAR_crio_version:-v1.34}" \
  terraform_apply_stack "$STACK_NAME"
KUBECONFIG_PATH="$(fetch_kubeconfig_from_stack "$STACK_NAME")"
EXPECTED_NODE_COUNT="$(
  terraform -chdir="$ROOT_DIR/terraform/stacks/$STACK_NAME" output -json \
    | jq -r '1 + (.worker_public_ips.value | length)'
)"
wait_for_nodes_ready "$KUBECONFIG_PATH" "$EXPECTED_NODE_COUNT"

TF_DIR="$ROOT_DIR/terraform/stacks/$STACK_NAME" \
KUBECONFIG_PATH="$KUBECONFIG_PATH" \
  "$ROOT_DIR/scripts/check-kata-prereqs.sh"

TF_DIR="$ROOT_DIR/terraform/stacks/$STACK_NAME" \
KUBECONFIG_PATH="$KUBECONFIG_PATH" \
  "$ROOT_DIR/scripts/install-kata.sh"

KUBECONFIG_PATH="$KUBECONFIG_PATH" \
  "$ROOT_DIR/scripts/verify-kata-runtime.sh"

echo "[INFO] K3s + CRI-O + Kata 1.34 candidate is ready at $KUBECONFIG_PATH"
