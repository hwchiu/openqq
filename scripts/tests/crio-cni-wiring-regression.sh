#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  local file="$1"
  local needle="$2"
  local context="$3"

  if ! grep -Fq -- "$needle" "$file"; then
    fail "$context ($file missing '$needle')"
  fi
}

assert_not_contains() {
  local file="$1"
  local needle="$2"
  local context="$3"

  if grep -Fq -- "$needle" "$file"; then
    fail "$context ($file unexpectedly contains '$needle')"
  fi
}

assert_line_order() {
  local file="$1"
  local first="$2"
  local second="$3"
  local context="$4"
  local first_line
  local second_line

  first_line="$(grep -nF -- "$first" "$file" | head -n1 | cut -d: -f1)"
  second_line="$(grep -nF -- "$second" "$file" | head -n1 | cut -d: -f1)"

  if [[ -z "$first_line" || -z "$second_line" || "$first_line" -ge "$second_line" ]]; then
    fail "$context ($file expected '$first' before '$second')"
  fi
}

server_template="$ROOT_DIR/terraform/templates/cloud-init-server.yaml.tftpl"
agent_template="$ROOT_DIR/terraform/templates/cloud-init-agent.yaml.tftpl"

assert_contains "$server_template" '--flannel-backend=none' \
  'CRI-O server installs should disable the embedded flannel backend'

for template in "$server_template" "$agent_template"; do
  assert_not_contains "$template" '/etc/rancher/k3s/10-flannel.conflist' \
    'CRI-O installs should not ship a pinned flannel CNI config'
  assert_not_contains "$template" '--flannel-cni-conf /etc/rancher/k3s/10-flannel.conflist' \
    'CRI-O installs should no longer point K3s at a flannel CNI config'
done

assert_not_contains "$agent_template" '--flannel-backend=none' \
  'CRI-O agent installs should not pass server-only flannel backend flags'

for script in \
  "$ROOT_DIR/scripts/install-k3s-crio.sh" \
  "$ROOT_DIR/scripts/install-k3s-crio-134.sh" \
  "$ROOT_DIR/scripts/install-k3s-gvisor.sh" \
  "$ROOT_DIR/scripts/install-k3s-gvisor-134.sh" \
  "$ROOT_DIR/scripts/install-k3s-openshell-runc.sh" \
  "$ROOT_DIR/scripts/install-k3s-openshell-runc-134.sh" \
  "$ROOT_DIR/scripts/install-k3s-openshell-gvisor.sh" \
  "$ROOT_DIR/scripts/install-k3s-openshell-gvisor-134.sh" \
  "$ROOT_DIR/scripts/install-k3s-kubearmor-runc.sh" \
  "$ROOT_DIR/scripts/install-k3s-kubearmor-runc-134.sh"; do
  assert_contains "$script" 'scripts/install-cilium-stack.sh' \
    'CRI-O family install paths should bootstrap Cilium before candidate-specific verification'
  assert_contains "$script" 'wait_for_node_count' \
    'CRI-O family install paths should wait for node registration before installing Cilium'
  assert_line_order "$script" 'wait_for_node_count' 'scripts/install-cilium-stack.sh' \
    'CRI-O family install paths should install Cilium after nodes are registered'
  assert_line_order "$script" 'scripts/install-cilium-stack.sh' 'wait_for_nodes_ready' \
    'CRI-O family install paths should only wait for Ready after Cilium is installed'
done

assert_not_contains "$ROOT_DIR/scripts/install-gvisor-stack.sh" '10-flannel.conflist' \
  'gVisor helper should not carry legacy flannel patching logic'

printf 'PASS: CRI-O CNI wiring regression checks\n'
