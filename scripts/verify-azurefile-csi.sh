#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_KUBECONFIG="$ROOT_DIR/generated/stacks/k3s-kata-134/kubeconfig"
DEFAULT_TF_DIR="$ROOT_DIR/terraform/stacks/k3s-kata-134"

exec "$ROOT_DIR/scripts/tests/kata-azurefile-csi-nfs.sh" \
  "${1:-${KUBECONFIG_PATH:-$DEFAULT_KUBECONFIG}}" \
  "${2:-${TF_DIR:-$DEFAULT_TF_DIR}}" \
  "${3:-${STACK_NAME:-k3s-kata-134}}"
