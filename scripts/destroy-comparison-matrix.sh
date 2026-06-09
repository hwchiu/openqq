#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib-stack.sh
source "$ROOT_DIR/scripts/lib-stack.sh"

STACKS=(
  k3s-crio
  k3s-gvisor
  k3s-openshell-runc
  k3s-openshell-gvisor
  k3s-kubearmor-runc
)

BASELINE_SUFFIX="${BASELINE_SUFFIX:-}"

for base_stack in "${STACKS[@]}"; do
  stack="${base_stack}${BASELINE_SUFFIX}"
  echo "[INFO] Destroying $stack"
  terraform_destroy_stack "$stack"
done
