#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${AZURE_ENV_FILE:-$ROOT_DIR/env/azure.env.example}"

if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi

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

require_var() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    fail "Missing required variable: $name"
  fi
}

print_summary() {
  cat <<EOF
Azure preflight summary
  access mode      : ${AZURE_ACCESS_MODE:-unset}
  subscription id  : ${AZURE_SUBSCRIPTION_ID:-unset}
  tenant id        : ${AZURE_TENANT_ID:-unset}
  region           : ${AZURE_REGION:-unset}
  mcp server       : ${AZURE_MCP_SERVER:-not specified}
  env file         : $ENV_FILE
EOF
}

check_common_inputs() {
  require_var AZURE_SUBSCRIPTION_ID
  require_var AZURE_TENANT_ID
  require_var AZURE_REGION
}

run_cli_preflight() {
  command -v az >/dev/null 2>&1 || fail "Azure CLI not found. Install 'az' or switch to MCP mode."

  log "Checking Azure CLI availability"
  az version >/dev/null

  if ! az account show >/dev/null 2>&1; then
    if [[ -n "${AZURE_CLIENT_ID:-}" && -n "${AZURE_CLIENT_SECRET:-}" ]]; then
      log "Logging in with service principal"
      az login --service-principal \
        --username "$AZURE_CLIENT_ID" \
        --password "$AZURE_CLIENT_SECRET" \
        --tenant "$AZURE_TENANT_ID" >/dev/null
    else
      fail "Azure CLI is not logged in. Run 'az login' or set service principal variables."
    fi
  fi

  log "Selecting subscription"
  az account set --subscription "$AZURE_SUBSCRIPTION_ID"

  local active_subscription
  active_subscription="$(az account show --query id -o tsv)"
  [[ "$active_subscription" == "$AZURE_SUBSCRIPTION_ID" ]] || fail "Active subscription does not match AZURE_SUBSCRIPTION_ID"

  log "Checking region visibility"
  az account list-locations --query "[?name=='$AZURE_REGION'].name" -o tsv | grep -qx "$AZURE_REGION" \
    || fail "Region '$AZURE_REGION' is not visible to the current identity"

  log "Checking Microsoft.Compute provider visibility"
  az provider show --namespace Microsoft.Compute --query registrationState -o tsv >/dev/null

  log "Checking VM SKU visibility"
  az vm list-skus \
    --location "$AZURE_REGION" \
    --resource-type virtualMachines \
    --query "[0].name" \
    -o tsv >/dev/null

  log "Checking regional quota visibility"
  az vm list-usage --location "$AZURE_REGION" --query "[0].name.value" -o tsv >/dev/null

  log "CLI preflight completed successfully"
}

run_mcp_preflight() {
  log "MCP mode selected"

  cat <<EOF
[ACTION REQUIRED]
This repository cannot probe Azure MCP directly from a shell script.

The next model/runtime must verify:
  1. An Azure MCP server is configured and reachable
  2. The server can inspect subscription ${AZURE_SUBSCRIPTION_ID}
  3. The server can inspect region ${AZURE_REGION}
  4. The server can query SKUs, quota, and resource providers
  5. The server identity can create the required Azure resources

Recommended MCP follow-up:
  - list available MCP servers/resources
  - identify the Azure MCP server name
  - query subscription, region, SKU, and quota through MCP

Fallback:
  Set AZURE_ACCESS_MODE=cli and rerun this script if Azure MCP is not exposed.
EOF

  if [[ -z "${AZURE_MCP_SERVER:-}" ]]; then
    warn "AZURE_MCP_SERVER is not set. Record the actual MCP server name when the runtime exposes it."
  else
    log "Expected Azure MCP server: $AZURE_MCP_SERVER"
  fi
}

main() {
  check_common_inputs
  print_summary

  case "${AZURE_ACCESS_MODE:-}" in
    mcp)
      run_mcp_preflight
      ;;
    cli)
      run_cli_preflight
      ;;
    *)
      fail "Unsupported AZURE_ACCESS_MODE '${AZURE_ACCESS_MODE:-unset}'. Use 'mcp' or 'cli'."
      ;;
  esac
}

main "$@"

