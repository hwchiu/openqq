#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
GENERATED_DIR="$ROOT_DIR/generated"
mkdir -p "$GENERATED_DIR"

fetch_from_terraform() {
  local tf_dir tmp_config cp_public_ip fetch_cmd
  tf_dir="$ROOT_DIR/terraform"

  command -v terraform >/dev/null 2>&1 || return 1
  [[ -d "$tf_dir" ]] || return 1

  cp_public_ip="$(terraform -chdir="$tf_dir" output -raw control_plane_public_ip 2>/dev/null)" || return 1
  fetch_cmd="$(terraform -chdir="$tf_dir" output -raw kubeconfig_fetch_command 2>/dev/null)" || return 1
  tmp_config="$GENERATED_DIR/kubeconfig.raw"

  (cd "$ROOT_DIR" && eval "$fetch_cmd")
  sed "s/127.0.0.1/$cp_public_ip/g" "$ROOT_DIR/generated/kubeconfig.raw" >"$GENERATED_DIR/kubeconfig"
  chmod 600 "$GENERATED_DIR/kubeconfig"

  printf '[INFO] Wrote kubeconfig to %s\n' "$GENERATED_DIR/kubeconfig"
}

fetch_from_legacy_env() {
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/lib-cluster.sh"

  cluster_preflight

  local key_path cp_public_ip tmp_config
  key_path="$(default_private_key)"
  cp_public_ip="$(get_public_ip "$CONTROL_PLANE_NAME")"
  tmp_config="$GENERATED_DIR/kubeconfig.raw"

  log "Fetching kubeconfig from control plane"
  scp_safe -i "$key_path" "$AZURE_ADMIN_USERNAME@$cp_public_ip:/etc/rancher/k3s/k3s.yaml" "$tmp_config"

  sed "s/127.0.0.1/$cp_public_ip/g" "$tmp_config" >"$GENERATED_DIR/kubeconfig"
  chmod 600 "$GENERATED_DIR/kubeconfig"

  log "Wrote kubeconfig to $GENERATED_DIR/kubeconfig"
}

main() {
  if fetch_from_terraform; then
    return 0
  fi

  fetch_from_legacy_env
}

main "$@"
