#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib-stack.sh
source "$ROOT_DIR/scripts/lib-stack.sh"

STACKS=(
  k3s-gvisor
  k3s-openshell-runc
  k3s-openshell-gvisor
  k3s-kubearmor-runc
)

for stack in "${STACKS[@]}"; do
  echo "[INFO] Destroying $stack"
  terraform_destroy_stack "$stack"
done
