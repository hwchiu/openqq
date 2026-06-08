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
  echo "[INFO] Installing $stack"
  "$ROOT_DIR/scripts/install-${stack}.sh"
done

echo "[INFO] Comparison matrix complete"
