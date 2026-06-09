#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STACKS_DIR="$ROOT_DIR/terraform/stacks"
GENERATED_STACKS_DIR="$ROOT_DIR/generated/stacks"
mkdir -p "$GENERATED_STACKS_DIR"

log() {
  printf '[INFO] %s\n' "$*"
}

fail() {
  printf '[ERROR] %s\n' "$*" >&2
  exit 1
}

require_bin() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing binary: $1"
}

default_ssh_args() {
  local -a args
  args=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null)
  if [[ -n "${AZURE_SSH_PRIVATE_KEY_PATH:-}" ]]; then
    args+=(-i "${AZURE_SSH_PRIVATE_KEY_PATH}")
  fi
  printf '%s\n' "${args[@]}"
}

load_default_ssh_args() {
  local __target="$1"
  eval "$__target=()"
  while IFS= read -r line; do
    eval "$__target+=(\"\$line\")"
  done < <(default_ssh_args)
}

resolve_stack_dir() {
  local stack_name="$1"
  local stack_dir="$STACKS_DIR/$stack_name"
  [[ -d "$stack_dir" ]] || fail "Unknown stack: $stack_name"
  printf '%s\n' "$stack_dir"
}

extract_hcl_string() {
  local key="$1"
  local file="$2"
  sed -nE "s/^${key}[[:space:]]*=[[:space:]]*\"(.*)\"$/\1/p" "$file" | tail -n1
}

render_shared_var_file() {
  local out_file="$GENERATED_STACKS_DIR/common.auto.tfvars"
  local root_tfvars="$ROOT_DIR/terraform/terraform.tfvars"
  local subscription_id="${AZURE_SUBSCRIPTION_ID:-}"
  local tenant_id="${AZURE_TENANT_ID:-}"
  local location="${AZURE_LOCATION:-}"
  local admin_username="${AZURE_ADMIN_USERNAME:-}"
  local ssh_public_key="${AZURE_SSH_PUBLIC_KEY:-}"

  if [[ -z "$ssh_public_key" && -n "${AZURE_SSH_PUBLIC_KEY_PATH:-}" && -f "${AZURE_SSH_PUBLIC_KEY_PATH}" ]]; then
    ssh_public_key="$(<"${AZURE_SSH_PUBLIC_KEY_PATH}")"
  fi

  if [[ -f "$STACKS_DIR/common.auto.tfvars" ]]; then
    printf '%s\n' "$STACKS_DIR/common.auto.tfvars"
    return 0
  fi

  if [[ -f "$root_tfvars" ]]; then
    [[ -n "$subscription_id" ]] || subscription_id="$(extract_hcl_string subscription_id "$root_tfvars")"
    [[ -n "$tenant_id" ]] || tenant_id="$(extract_hcl_string tenant_id "$root_tfvars")"
    [[ -n "$location" ]] || location="$(extract_hcl_string location "$root_tfvars")"
    [[ -n "$admin_username" ]] || admin_username="$(extract_hcl_string admin_username "$root_tfvars")"
    [[ -n "$ssh_public_key" ]] || ssh_public_key="$(extract_hcl_string ssh_public_key "$root_tfvars")"
  fi

  [[ -n "$subscription_id" ]] || fail "subscription_id not found; set AZURE_SUBSCRIPTION_ID or terraform/stacks/common.auto.tfvars"
  [[ -n "$tenant_id" ]] || fail "tenant_id not found; set AZURE_TENANT_ID or terraform/stacks/common.auto.tfvars"
  [[ -n "$ssh_public_key" ]] || fail "ssh_public_key not found; set AZURE_SSH_PUBLIC_KEY, AZURE_SSH_PUBLIC_KEY_PATH, or terraform/stacks/common.auto.tfvars"
  [[ -n "$location" ]] || location="eastus"
  [[ -n "$admin_username" ]] || admin_username="azureuser"

  cat > "$out_file" <<VARS
subscription_id = "$subscription_id"
tenant_id       = "$tenant_id"
location        = "$location"
admin_username  = "$admin_username"
ssh_public_key  = "$ssh_public_key"
VARS

  printf '%s\n' "$out_file"
}

terraform_apply_stack() {
  local stack_name="$1"
  local stack_dir
  local shared_var_file
  stack_dir="$(resolve_stack_dir "$stack_name")"
  shared_var_file="$(render_shared_var_file)"

  require_bin terraform
  log "terraform init: $stack_name"
  terraform -chdir="$stack_dir" init
  log "terraform apply: $stack_name"
  terraform -chdir="$stack_dir" apply -auto-approve -var-file="$shared_var_file"
}

terraform_destroy_stack() {
  local stack_name="$1"
  local stack_dir
  local shared_var_file
  stack_dir="$(resolve_stack_dir "$stack_name")"
  shared_var_file="$(render_shared_var_file)"

  require_bin terraform
  terraform -chdir="$stack_dir" init >/dev/null
  terraform -chdir="$stack_dir" destroy -auto-approve -var-file="$shared_var_file"
}

fetch_kubeconfig_from_stack() {
  local stack_name="$1"
  local stack_dir
  local out_dir
  local cp_public_ip
  local admin_username
  local -a scp_args
  local attempt
  stack_dir="$(resolve_stack_dir "$stack_name")"
  out_dir="$GENERATED_STACKS_DIR/$stack_name"
  mkdir -p "$out_dir"

  require_bin terraform
  require_bin scp
  cp_public_ip="$(terraform -chdir="$stack_dir" output -raw control_plane_public_ip)"
  admin_username="$(terraform -chdir="$stack_dir" output -raw admin_username)"
  load_default_ssh_args scp_args
  for attempt in $(seq 1 90); do
    if scp "${scp_args[@]}" "$admin_username@$cp_public_ip:/etc/rancher/k3s/k3s.yaml" "$out_dir/kubeconfig.raw" >/dev/null 2>&1; then
      break
    fi
    sleep 10
  done
  [[ -f "$out_dir/kubeconfig.raw" ]] || fail "kubeconfig not ready on control plane for stack $stack_name"
  sed "s/127.0.0.1/$cp_public_ip/g" "$out_dir/kubeconfig.raw" > "$out_dir/kubeconfig"
  chmod 600 "$out_dir/kubeconfig"
  printf '%s\n' "$out_dir/kubeconfig"
}

wait_for_ssh() {
  local host="$1"
  local -a ssh_args
  load_default_ssh_args ssh_args
  require_bin ssh
  for _ in $(seq 1 60); do
    if ssh "${ssh_args[@]}" "$host" true >/dev/null 2>&1; then
      return 0
    fi
    sleep 10
  done
  fail "SSH not ready: $host"
}

ssh_safe() {
  local -a ssh_args
  load_default_ssh_args ssh_args
  require_bin ssh
  ssh "${ssh_args[@]}" "$@"
}

wait_for_nodes_ready() {
  local kubeconfig_path="$1"
  require_bin kubectl
  kubectl --kubeconfig "$kubeconfig_path" wait --for=condition=Ready nodes --all --timeout=600s
}

stack_kubeconfig_path() {
  local stack_name="$1"
  printf '%s\n' "$GENERATED_STACKS_DIR/$stack_name/kubeconfig"
}
