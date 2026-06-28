#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KUBECONFIG_PATH="${KUBECONFIG_PATH:-$ROOT_DIR/generated/kubeconfig}"
TF_DIR="${TF_DIR:-$ROOT_DIR/terraform}"
SSH_KEY_PATH="${KATA_SSH_PRIVATE_KEY_PATH:-${AZURE_SSH_PRIVATE_KEY_PATH:-$HOME/.ssh/id_ed25519}}"
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
CONTROL_PLANE_IP="$(printf '%s' "$TF_JSON" | jq -r '.control_plane_public_ip.value')"
if [[ -n "$CONTROL_PLANE_IP" && "$CONTROL_PLANE_IP" != "null" ]]; then
  HOSTS+=("$CONTROL_PLANE_IP")
fi
while IFS= read -r host; do
  HOSTS+=("$host")
done < <(printf '%s' "$TF_JSON" | jq -r '.worker_public_ips.value[]')

find_vm_size() {
  local candidate
  for candidate in \
    "$TF_DIR/terraform.tfvars" \
    "$TF_DIR/stack.auto.tfvars" \
    "$TF_DIR/main.tf"; do
    [[ -f "$candidate" ]] || continue
    if sed -n 's/^vm_size[[:space:]]*=[[:space:]]*"\([^"]*\)"/\1/p' "$candidate" | head -n1 | grep -q .; then
      sed -n 's/^vm_size[[:space:]]*=[[:space:]]*"\([^"]*\)"/\1/p' "$candidate" | head -n1
      return 0
    fi
  done
  printf 'unknown\n'
}

VM_SIZE="$(find_vm_size)"

echo "[INFO] Terraform VM size: ${VM_SIZE:-unknown}"
echo "[INFO] Checking cluster nodes for Kata prerequisites..."

missing_kvm=0
for host in "${HOSTS[@]}"; do
  echo "=== $host ==="
  if ! ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "$SSH_KEY_PATH" "$SSH_USER@$host" '
    echo "hostname=$(hostname)"
    lscpu | egrep "Model name|Hypervisor vendor|Virtualization" || true
    if [ -e /dev/kvm ]; then
      echo "KVM_PRESENT"
    else
      echo "KVM_ABSENT"
    fi
    grep -m1 -E "vmx|svm" /proc/cpuinfo || true
  '; then
    echo "[ERROR] SSH or prerequisite check failed for $host" >&2
    exit 1
  fi
  if ! ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "$SSH_KEY_PATH" "$SSH_USER@$host" 'test -e /dev/kvm'; then
    missing_kvm=1
  fi
  echo
done

echo "[INFO] RuntimeClasses currently installed:"
kubectl --kubeconfig "$KUBECONFIG_PATH" get runtimeclass || true

echo "[INFO] Kata requires hardware virtualization support."
if [[ "$missing_kvm" -ne 0 ]]; then
  echo "[ERROR] One or more nodes are missing /dev/kvm. Change the Azure VM size before attempting Kata install." >&2
  exit 1
fi
echo "[INFO] All checked nodes expose /dev/kvm."
