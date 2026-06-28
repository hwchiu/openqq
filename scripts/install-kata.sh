#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KUBECONFIG_PATH="${KUBECONFIG_PATH:-$ROOT_DIR/generated/kubeconfig}"
TF_DIR="${TF_DIR:-$ROOT_DIR/terraform}"
SSH_KEY_PATH="${KATA_SSH_PRIVATE_KEY_PATH:-${AZURE_SSH_PRIVATE_KEY_PATH:-$HOME/.ssh/id_ed25519}}"
SSH_USER="${KATA_SSH_USER:-azureuser}"
KATA_VERSION="${KATA_VERSION:-3.31.0}"
KATA_ARCH="${KATA_ARCH:-amd64}"
KATA_RUNTIME_NAME="${KATA_RUNTIME_NAME:-kata}"
KATA_STORAGE_DROP_IN="${KATA_STORAGE_DROP_IN:-/etc/crio/crio.conf.d/01-storage-options.conf}"

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

read -r -d '' REMOTE_SCRIPT <<'REMOTE' || true
set -euo pipefail
KATA_VERSION="${KATA_VERSION}"
KATA_ARCH="${KATA_ARCH}"
KATA_RUNTIME_NAME="${KATA_RUNTIME_NAME}"
KATA_STORAGE_DROP_IN="${KATA_STORAGE_DROP_IN}"
ASSET_URL="https://github.com/kata-containers/kata-containers/releases/download/${KATA_VERSION}/kata-static-${KATA_VERSION}-${KATA_ARCH}.tar.zst"
TMP_ASSET="/tmp/kata-static-${KATA_VERSION}-${KATA_ARCH}.tar.zst"
KATA_SHIM_PATH="/usr/local/bin/containerd-shim-kata-v2"
CRIO_DROP_IN="/etc/crio/crio.conf.d/50-${KATA_RUNTIME_NAME}.conf"

if [ ! -e /dev/kvm ]; then
  echo "[ERROR] /dev/kvm is missing on $(hostname). Kata Containers requires hardware virtualization support." >&2
  exit 1
fi

sudo apt-get update -qq
sudo apt-get install -y curl zstd tar jq

curl -fsSL -o "$TMP_ASSET" "$ASSET_URL"
sudo tar --zstd -xf "$TMP_ASSET" -C /
rm -f "$TMP_ASSET"

if [ -x /opt/kata/bin/containerd-shim-kata-v2 ]; then
  sudo ln -sf /opt/kata/bin/containerd-shim-kata-v2 /usr/local/bin/containerd-shim-kata-v2
fi
if [ -x /opt/kata/bin/kata-runtime ]; then
  sudo ln -sf /opt/kata/bin/kata-runtime /usr/local/bin/kata-runtime
fi
if [ -x /opt/kata/bin/kata-ctl ]; then
  sudo ln -sf /opt/kata/bin/kata-ctl /usr/local/bin/kata-ctl
fi

if command -v containerd-shim-kata-v2 >/dev/null 2>&1; then
  KATA_SHIM_PATH="$(command -v containerd-shim-kata-v2)"
fi

sudo mkdir -p /etc/crio/crio.conf.d
sudo install -d -m 1777 /run/vc
cat <<TOML | sudo tee "$KATA_STORAGE_DROP_IN" >/dev/null
[crio]
storage_option = [
  "overlay.skip_mount_home=true",
]
TOML
cat <<TOML | sudo tee "$CRIO_DROP_IN" >/dev/null
[crio.runtime.runtimes.${KATA_RUNTIME_NAME}]
runtime_path = "${KATA_SHIM_PATH}"
runtime_type = "vm"
runtime_root = "/run/vc"
privileged_without_host_devices = true
TOML

sudo systemctl restart crio
if systemctl list-unit-files | grep -q '^k3s.service'; then
  sudo systemctl restart k3s
fi
if systemctl list-unit-files | grep -q '^k3s-agent.service'; then
  sudo systemctl restart k3s-agent
fi
sleep 5

if command -v kata-runtime >/dev/null 2>&1; then
  sudo kata-runtime check --no-network-checks || true
fi

echo "[INFO] Kata installation complete on $(hostname)"
REMOTE

for host in "${HOSTS[@]}"; do
  echo "[INFO] Installing Kata on $host"
  ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "$SSH_KEY_PATH" "$SSH_USER@$host" \
    "KATA_VERSION='$KATA_VERSION' KATA_ARCH='$KATA_ARCH' KATA_RUNTIME_NAME='$KATA_RUNTIME_NAME' KATA_STORAGE_DROP_IN='$KATA_STORAGE_DROP_IN' bash -s" <<< "$REMOTE_SCRIPT"
done

kubectl --kubeconfig "$KUBECONFIG_PATH" apply -f "$ROOT_DIR/k8s/kata-runtimeclass.yaml"
kubectl --kubeconfig "$KUBECONFIG_PATH" get runtimeclass kata

echo "[INFO] Kata runtime installed. Run 'make kata-verify' next."
