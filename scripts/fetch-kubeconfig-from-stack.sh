#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib-stack.sh
source "$ROOT_DIR/scripts/lib-stack.sh"

[[ $# -eq 1 ]] || fail "Usage: $0 <stack-name>"
fetch_kubeconfig_from_stack "$1"
