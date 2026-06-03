#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KUBECONFIG_PATH="${KUBECONFIG_PATH:-$ROOT_DIR/generated/kubeconfig}"
TF_DIR="${TF_DIR:-$ROOT_DIR/terraform}"
SSH_KEY_PATH="${KATA_SSH_PRIVATE_KEY_PATH:-$HOME/.ssh/id_ed25519}"
SSH_USER="${KATA_SSH_USER:-azureuser}"
KATA_VERSION="${KATA_VERSION:-3.31.0}"
KATA_ARCH="${KATA_ARCH:-amd64}"
KATA_RUNTIME_NAME="${KATA_RUNTIME_NAME:-kata}"

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

read -r -d '' REMOTE_SCRIPT <<'REMOTE' || true
set -euo pipefail
KATA_VERSION="${KATA_VERSION}"
KATA_ARCH="${KATA_ARCH}"
KATA_RUNTIME_NAME="${KATA_RUNTIME_NAME}"
ASSET_URL="https://github.com/kata-containers/kata-containers/releases/download/${KATA_VERSION}/kata-static-${KATA_VERSION}-${KATA_ARCH}.tar.zst"
TMP_ASSET="/tmp/kata-static-${KATA_VERSION}-${KATA_ARCH}.tar.zst"
CONFIG_TMPL="/var/lib/rancher/k3s/agent/etc/containerd/config-v3.toml.tmpl"

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

sudo mkdir -p "$(dirname "$CONFIG_TMPL")"
if [ -f "$CONFIG_TMPL" ] && grep -q "io.containerd.kata.v2" "$CONFIG_TMPL"; then
  echo "[INFO] Kata runtime already present in $CONFIG_TMPL"
else
  cat <<'TOML' | sudo tee "$CONFIG_TMPL" >/dev/null
{{ template "base" . }}

[plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.'kata']
  runtime_type = "io.containerd.kata.v2"
TOML
fi

sudo systemctl restart k3s-agent
sleep 5

if command -v kata-runtime >/dev/null 2>&1; then
  sudo kata-runtime check --no-network-checks || true
fi

echo "[INFO] Kata installation complete on $(hostname)"
REMOTE

for host in "${HOSTS[@]}"; do
  echo "[INFO] Installing Kata on $host"
  ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "$SSH_KEY_PATH" "$SSH_USER@$host" \
    "KATA_VERSION='$KATA_VERSION' KATA_ARCH='$KATA_ARCH' KATA_RUNTIME_NAME='$KATA_RUNTIME_NAME' bash -s" <<< "$REMOTE_SCRIPT"
done

kubectl --kubeconfig "$KUBECONFIG_PATH" apply -f "$ROOT_DIR/k8s/kata-runtimeclass.yaml"
kubectl --kubeconfig "$KUBECONFIG_PATH" get runtimeclass kata

echo "[INFO] Kata runtime installed. Run 'make kata-verify' next."
