#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib-cluster.sh"

main() {
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

main "$@"
