#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib-cluster.sh"

main() {
  [[ -f "$GENERATED_DIR/kubeconfig" ]] || fail "Missing kubeconfig at $GENERATED_DIR/kubeconfig"
  log "Querying cluster nodes"
  kubectl --kubeconfig "$GENERATED_DIR/kubeconfig" get nodes -o wide
}

main "$@"
