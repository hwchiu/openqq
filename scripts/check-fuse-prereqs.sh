#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="${TF_DIR:-$ROOT_DIR/terraform}"
KUBECONFIG_PATH="${KUBECONFIG_PATH:-$ROOT_DIR/generated/kubeconfig}"
SSH_KEY_PATH="${FUSE_SSH_PRIVATE_KEY_PATH:-$HOME/.ssh/id_ed25519}"
SSH_USER="${FUSE_SSH_USER:-azureuser}"

require_bin() {
  command -v "$1" >/dev/null 2>&1 || { echo "[ERROR] Missing binary: $1" >&2; exit 1; }
}

require_bin terraform
require_bin jq
require_bin ssh
require_bin kubectl

[[ -f "$SSH_KEY_PATH" ]] || { echo "[ERROR] SSH key not found at $SSH_KEY_PATH" >&2; exit 1; }
[[ -f "$KUBECONFIG_PATH" ]] || { echo "[ERROR] kubeconfig not found at $KUBECONFIG_PATH" >&2; exit 1; }

TF_JSON="$(terraform -chdir="$TF_DIR" output -json)"
HOSTS=()
while IFS= read -r host; do
  HOSTS+=("$host")
done < <(printf '%s' "$TF_JSON" | jq -r '.ssh_commands.value | to_entries[] | .value' | awk '{print $2}' | sed 's#.*@##')

echo "[INFO] Checking node-side FUSE prerequisites..."
for host in "${HOSTS[@]}"; do
  echo "=== $host ==="
  ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "$SSH_KEY_PATH" "$SSH_USER@$host" '
    echo "hostname=$(hostname)"
    if [ -e /dev/fuse ]; then echo "DEV_FUSE_PRESENT"; else echo "DEV_FUSE_MISSING"; fi
    lsmod | grep "^fuse" || echo "FUSE_MODULE_NOT_LOADED"
    command -v modprobe >/dev/null 2>&1 && sudo modprobe fuse >/dev/null 2>&1 || true
    if [ -e /dev/fuse ]; then ls -l /dev/fuse; fi
  '
  echo
done

echo "[INFO] Cluster runtime baseline:"
kubectl --kubeconfig "$KUBECONFIG_PATH" get nodes -o wide
