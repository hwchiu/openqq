#!/usr/bin/env bash
# Installs gVisor (runsc) on all worker nodes in the existing k3s cluster.
# Prerequisites: cluster must be up, generated/cluster.env and SSH key must exist.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib-cluster.sh
source "$ROOT_DIR/scripts/lib-cluster.sh"

KUBECONFIG_PATH="${KUBECONFIG_PATH:-$ROOT_DIR/generated/kubeconfig}"
CLUSTER_ENV="$ROOT_DIR/generated/cluster.env"

[[ -f "$CLUSTER_ENV" ]] || fail "generated/cluster.env not found – run 'make cluster-up' first"
# shellcheck source=/dev/null
source "$CLUSTER_ENV"

PRIVATE_KEY="$(default_private_key)"
WORKER_NAMES=("${WORKER1_NAME}" "${WORKER2_NAME}")

INSTALL_SCRIPT=$(cat << 'REMOTE'
#!/bin/bash
set -euxo pipefail

# --- 1. Install gVisor apt package ---
if ! command -v runsc >/dev/null 2>&1; then
  curl -fsSL https://gvisor.dev/archive.key \
    | gpg --batch --yes --dearmor -o /usr/share/keyrings/gvisor-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/gvisor-archive-keyring.gpg] \
https://storage.googleapis.com/gvisor/releases release main" \
    | tee /etc/apt/sources.list.d/gvisor.list > /dev/null
  apt-get update -qq
  apt-get install -y runsc
fi

runsc --version

# --- 2. Detect container runtime (CRI-O vs k3s containerd) and configure accordingly ---
if systemctl is-enabled --quiet crio 2>/dev/null; then
  echo "Detected CRI-O — configuring /etc/crio/crio.conf.d/10-runsc.conf"
  mkdir -p /etc/crio/crio.conf.d
  CONMON_PATH="$(command -v conmon 2>/dev/null || echo /usr/libexec/crio/conmon)"
  cat > /etc/crio/crio.conf.d/10-runsc.conf << CRIOCFG
[crio.runtime.runtimes.runsc]
  runtime_path = ""
  runtime_type = "oci"
  runtime_root = "/run/runsc"
  privileged_without_host_devices = false
  monitor_path = "${CONMON_PATH}"
CRIOCFG
  systemctl restart crio
  sleep 3
  # Restart k3s-agent so kubelet re-registers node with updated runtime info
  systemctl restart k3s-agent
else
  echo "Detected k3s containerd — configuring config.toml.tmpl"
  CONFIG_TMPL="/var/lib/rancher/k3s/agent/etc/containerd/config.toml.tmpl"
  if [[ ! -f "$CONFIG_TMPL" ]]; then
    mkdir -p "$(dirname "$CONFIG_TMPL")"
    k3s containerd config default > "$CONFIG_TMPL"
  fi
  if ! grep -q 'runsc' "$CONFIG_TMPL"; then
    cat >> "$CONFIG_TMPL" << 'TOML'

[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runsc]
  runtime_type = "io.containerd.runsc.v1"
TOML
  fi
  systemctl restart k3s-agent
fi

echo "gVisor installation complete on $(hostname)"
REMOTE
)

log "Installing gVisor on worker nodes: ${WORKER_NAMES[*]}"

for worker in "${WORKER_NAMES[@]}"; do
  log "→ Processing $worker"
  ip="$(get_public_ip "$worker")"
  wait_for_ssh "$ip" "$PRIVATE_KEY"
  ssh_safe -i "$PRIVATE_KEY" "${AZURE_ADMIN_USERNAME}@${ip}" "sudo bash -s" <<< "$INSTALL_SCRIPT"
  log "✓ $worker done"
done

log "Applying RuntimeClass to cluster…"
kubectl --kubeconfig "$KUBECONFIG_PATH" apply -f "$ROOT_DIR/k8s/gvisor-runtimeclass.yaml"
kubectl --kubeconfig "$KUBECONFIG_PATH" get runtimeclass gvisor

log "gVisor setup complete. Run 'make gvisor-verify' to confirm."
