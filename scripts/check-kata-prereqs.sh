#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KUBECONFIG_PATH="${KUBECONFIG_PATH:-$ROOT_DIR/generated/kubeconfig}"
TF_DIR="${TF_DIR:-$ROOT_DIR/terraform}"
SSH_KEY_PATH="${KATA_SSH_PRIVATE_KEY_PATH:-$HOME/.ssh/id_ed25519}"
SSH_USER="${KATA_SSH_USER:-azureuser}"

require_bin() {
  command -v "$1" >/dev/null 2>&1 || { echo "[ERROR] Missing binary: $1" >&2; exit 1; }
}

require_bin terraform
require_bin jq
require_bin ssh
require_bin kubectl

[[ -f "$KUBECONFIG_PATH" ]] || { echo "[ERROR] kubeconfig not found at $KUBECONFIG_PATH" >&2; exit 1; }
[[ -f "$SSH_KEY_PATH" ]] || { echo "[ERROR] SSH key not found at $SSH_KEY_PATH" >&2; exit 1; }

TF_JSON="$(terraform -chdir="$TF_DIR" output -json)"
HOSTS=()
while IFS= read -r host; do
  HOSTS+=("$host")
done < <(printf '%s' "$TF_JSON" | jq -r '.worker_public_ips.value[]')
VM_SIZE="$(sed -n 's/^vm_size[[:space:]]*=[[:space:]]*"\([^"]*\)"/\1/p' "$TF_DIR/terraform.tfvars" | head -n1)"

echo "[INFO] Terraform VM size: ${VM_SIZE:-unknown}"
echo "[INFO] Checking worker nodes for Kata prerequisites..."

for host in "${HOSTS[@]}"; do
  echo "=== $host ==="
  ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "$SSH_KEY_PATH" "$SSH_USER@$host" '
    echo "hostname=$(hostname)"
    lscpu | egrep "Model name|Hypervisor vendor|Virtualization" || true
    if [ -e /dev/kvm ]; then
      echo "KVM_PRESENT"
    else
      echo "KVM_ABSENT"
    fi
    grep -m1 -E "vmx|svm" /proc/cpuinfo || true
  '
  echo
 done

echo "[INFO] RuntimeClasses currently installed:"
kubectl --kubeconfig "$KUBECONFIG_PATH" get runtimeclass || true

echo "[INFO] Kata requires hardware virtualization support."
echo "[INFO] If workers show KVM_ABSENT, change Azure VM size before attempting install."
