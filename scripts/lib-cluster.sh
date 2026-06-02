#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${AZURE_ENV_FILE:-$ROOT_DIR/.env}"

if [[ ! -f "$ENV_FILE" ]]; then
  ENV_FILE="$ROOT_DIR/env/azure.env.example"
fi

# shellcheck disable=SC1090
source "$ENV_FILE"

GENERATED_DIR="$ROOT_DIR/generated"
mkdir -p "$GENERATED_DIR"

log() {
  printf '[INFO] %s\n' "$1"
}

warn() {
  printf '[WARN] %s\n' "$1" >&2
}

fail() {
  printf '[ERROR] %s\n' "$1" >&2
  exit 1
}

require_bin() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing required binary: $1"
}

require_var() {
  local name="$1"
  [[ -n "${!name:-}" ]] || fail "Missing required variable: $name"
}

az_safe() {
  if [[ -n "${AZURE_CONFIG_DIR:-}" ]]; then
    AZURE_CONFIG_DIR="$AZURE_CONFIG_DIR" az "$@"
  else
    az "$@"
  fi
}

ssh_safe() {
  ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$@"
}

scp_safe() {
  scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$@"
}

cluster_preflight() {
  require_bin az
  require_bin ssh
  require_bin scp
  require_bin kubectl
  require_var AZURE_SUBSCRIPTION_ID
  require_var AZURE_REGION
  require_var AZURE_RESOURCE_GROUP
  require_var AZURE_VM_SIZE
  require_var AZURE_ADMIN_USERNAME
  require_var AZURE_SSH_PUBLIC_KEY_PATH
  require_var AZURE_VNET_NAME
  require_var AZURE_SUBNET_NAME
  require_var AZURE_NSG_NAME
  require_var AZURE_VNET_CIDR
  require_var AZURE_SUBNET_CIDR
  require_var K3S_CLUSTER_CIDR
  require_var K3S_SERVICE_CIDR
  require_var CONTROL_PLANE_NAME
  require_var WORKER1_NAME
  require_var WORKER2_NAME

  [[ -f "$AZURE_SSH_PUBLIC_KEY_PATH" ]] || fail "SSH public key not found at $AZURE_SSH_PUBLIC_KEY_PATH"

  az_safe account set --subscription "$AZURE_SUBSCRIPTION_ID" >/dev/null
}

get_public_ip() {
  local vm_name="$1"
  az_safe vm show -d -g "$AZURE_RESOURCE_GROUP" -n "$vm_name" --query publicIps -o tsv
}

get_private_ip() {
  local vm_name="$1"
  az_safe vm show -d -g "$AZURE_RESOURCE_GROUP" -n "$vm_name" --query privateIps -o tsv
}

wait_for_ssh() {
  local host="$1"
  local key_path="$2"
  local user="$AZURE_ADMIN_USERNAME"

  for _ in $(seq 1 60); do
    if ssh_safe -i "$key_path" "$user@$host" 'echo ready' >/dev/null 2>&1; then
      return 0
    fi
    sleep 10
  done

  fail "SSH did not become ready for $host"
}

default_private_key() {
  local pub="$AZURE_SSH_PUBLIC_KEY_PATH"
  if [[ "$pub" == *.pub ]]; then
    printf '%s' "${pub%.pub}"
  else
    fail "AZURE_SSH_PUBLIC_KEY_PATH must point to a .pub file"
  fi
}

write_cluster_metadata() {
  cat >"$GENERATED_DIR/cluster.env" <<EOF
export AZURE_RESOURCE_GROUP="$AZURE_RESOURCE_GROUP"
export AZURE_REGION="$AZURE_REGION"
export CONTROL_PLANE_NAME="$CONTROL_PLANE_NAME"
export WORKER1_NAME="$WORKER1_NAME"
export WORKER2_NAME="$WORKER2_NAME"
export AZURE_ADMIN_USERNAME="$AZURE_ADMIN_USERNAME"
export AZURE_SSH_PUBLIC_KEY_PATH="$AZURE_SSH_PUBLIC_KEY_PATH"
export K3S_CLUSTER_CIDR="$K3S_CLUSTER_CIDR"
export K3S_SERVICE_CIDR="$K3S_SERVICE_CIDR"
EOF
}
