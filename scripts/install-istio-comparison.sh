#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STACKS=(
  k3s-gvisor
  k3s-openshell-runc
  k3s-openshell-gvisor
  k3s-kubearmor-runc
)

for stack in "${STACKS[@]}"; do
  kubeconfig="$ROOT_DIR/generated/stacks/$stack/kubeconfig"
  if [[ ! -f "$kubeconfig" ]]; then
    echo "[WARN] skipping $stack: kubeconfig missing at $kubeconfig" >&2
    continue
  fi
  echo "[INFO] Installing Istio on $stack"
  "$ROOT_DIR/scripts/install-istio-stack.sh" "$stack" "$kubeconfig"
done
