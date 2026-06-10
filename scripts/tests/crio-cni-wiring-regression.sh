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

server_template="$ROOT_DIR/terraform/templates/cloud-init-server.yaml.tftpl"
agent_template="$ROOT_DIR/terraform/templates/cloud-init-agent.yaml.tftpl"

for template in "$server_template" "$agent_template"; do
  assert_contains "$template" '/etc/rancher/k3s/10-flannel.conflist' \
    'CRI-O installs should pin a custom flannel CNI config path'
  assert_contains "$template" '--flannel-cni-conf /etc/rancher/k3s/10-flannel.conflist' \
    'CRI-O installs should tell K3s to use the pinned flannel CNI config'
  assert_contains "$template" '"type":"portmap"' \
    'Pinned flannel CNI config should keep the portmap plugin'
  assert_not_contains "$template" '"type":"bandwidth"' \
    'Pinned flannel CNI config should not inject the crashing bandwidth plugin'
done

printf 'PASS: CRI-O CNI wiring regression checks\n'
