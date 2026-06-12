#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STACK_NAME="k3s-kubearmor-runc"
# shellcheck source=scripts/lib-stack.sh
source "$ROOT_DIR/scripts/lib-stack.sh"

terraform_apply_stack "$STACK_NAME"
KUBECONFIG_PATH="$(fetch_kubeconfig_from_stack "$STACK_NAME")"
wait_for_node_count "$KUBECONFIG_PATH" 3
KUBECONFIG_PATH="$KUBECONFIG_PATH" "$ROOT_DIR/scripts/install-cilium-stack.sh"
wait_for_nodes_ready "$KUBECONFIG_PATH"
KUBECONFIG_PATH="$KUBECONFIG_PATH" "$ROOT_DIR/scripts/install-kubearmor-stack.sh"
KUBECONFIG_PATH="$KUBECONFIG_PATH" "$ROOT_DIR/scripts/verify-kubearmor-runtime.sh"
