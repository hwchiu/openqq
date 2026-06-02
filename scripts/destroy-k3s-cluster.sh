#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib-cluster.sh"

main() {
  cluster_preflight
  log "Deleting resource group $AZURE_RESOURCE_GROUP"
  az_safe group delete --name "$AZURE_RESOURCE_GROUP" --yes --no-wait
  log "Delete request submitted"
}

main "$@"
