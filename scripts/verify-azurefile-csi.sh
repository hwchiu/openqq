#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_KUBECONFIG="$ROOT_DIR/generated/stacks/k3s-kata-134/kubeconfig"
DEFAULT_TF_DIR="$ROOT_DIR/terraform/stacks/k3s-kata-134"
PROFILE="${AZUREFILE_CSI_PROFILE:-smb}"

case "$PROFILE" in
  smb)
    TARGET_SCRIPT="$ROOT_DIR/scripts/tests/kata-azurefile-csi-smb.sh"
    ;;
  nfs)
    TARGET_SCRIPT="$ROOT_DIR/scripts/tests/kata-azurefile-csi-nfs.sh"
    ;;
  *)
    echo "unsupported AZUREFILE_CSI_PROFILE: $PROFILE (expected: smb or nfs)" >&2
    exit 1
    ;;
esac

exec "$TARGET_SCRIPT" \
  "${1:-${KUBECONFIG_PATH:-$DEFAULT_KUBECONFIG}}" \
  "${2:-${TF_DIR:-$DEFAULT_TF_DIR}}" \
  "${3:-${STACK_NAME:-k3s-kata-134}}"
