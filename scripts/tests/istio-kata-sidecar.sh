#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export RUNTIME_CLASS_NAME="${RUNTIME_CLASS_NAME:-kata}"
export EXPECTED_RESPONSE="${EXPECTED_RESPONSE:-kata-mesh-ok}"
export NAMESPACE_PREFIX="${NAMESPACE_PREFIX:-istio-kata-smoke}"

"$ROOT_DIR/istio-sidecar-smoke.sh" "$@"
