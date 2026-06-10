#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STACK_NAME="k3s-openshell-runc"
# shellcheck source=scripts/lib-stack.sh
source "$ROOT_DIR/scripts/lib-stack.sh"

terraform_apply_stack "$STACK_NAME"
KUBECONFIG_PATH="$(fetch_kubeconfig_from_stack "$STACK_NAME")"
wait_for_nodes_ready "$KUBECONFIG_PATH"
KUBECONFIG_PATH="$KUBECONFIG_PATH" "$ROOT_DIR/scripts/install-cilium-stack.sh"
KUBECONFIG_PATH="$KUBECONFIG_PATH" "$ROOT_DIR/scripts/install-openshell-stack.sh"
KUBECONFIG_PATH="$KUBECONFIG_PATH" TERRAFORM_DIR="$ROOT_DIR/terraform/stacks/$STACK_NAME" "$ROOT_DIR/scripts/verify-openshell-runtime.sh"
