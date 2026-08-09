#!/usr/bin/env bash
set -euo pipefail

# Fast post-deployment gate for a new company cluster.
# Required: curl, jq. kubectl is required when CHECK_K8S=1 (the default).
# Example:
#   TENANT_SERVER_URL=http://10.10.0.154:30081 \
#   DEMO_SERVER_URL=http://10.10.0.154:30080 \
#   CHECK_PROMETHEUS=1 ./deployment-smoke.sh

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TENANT_SERVER_URL="${TENANT_SERVER_URL:-http://127.0.0.1:30081}"
DEMO_SERVER_URL="${DEMO_SERVER_URL:-}"
KFA_BASE_URL="${KFA_BASE_URL:-http://10.10.0.48:30082}"
CHECK_K8S="${CHECK_K8S:-1}"
CHECK_PROMETHEUS="${CHECK_PROMETHEUS:-0}"
CHECK_KFA="${CHECK_KFA:-1}"

fail() { echo "FAIL: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || fail "missing command: $1"; }
get() { curl -fsS --retry 4 --retry-delay 1 --retry-connrefused --max-time 20 "$@"; }

need curl
need jq
if [[ "$CHECK_K8S" == 1 ]]; then need kubectl; fi

echo "== OpenSandbox deployment smoke test =="
echo "Tenant Server: $TENANT_SERVER_URL"
[[ -n "$DEMO_SERVER_URL" ]] && echo "Demo Server: $DEMO_SERVER_URL"

tenant_health="$(get "$TENANT_SERVER_URL/health")"
[[ "$(jq -r .status <<<"$tenant_health")" == ok ]] || fail "Tenant Server health: $tenant_health"
[[ "$(jq -r .store <<<"$tenant_health")" == postgres ]] || fail "Tenant Server is not using PostgreSQL: $tenant_health"
echo "PASS: Tenant Server health and PostgreSQL"

if [[ -n "$DEMO_SERVER_URL" ]]; then
  demo_health="$(get "$DEMO_SERVER_URL/health")"
  [[ "$(jq -r .status <<<"$demo_health")" == ok ]] || fail "Demo Server health: $demo_health"
  echo "PASS: Demo Server health"
fi

if [[ "$CHECK_K8S" == 1 ]]; then
  kubectl -n opensandbox-tenant-server rollout status deployment/opensandbox-tenant-server --timeout=120s
  kubectl -n opensandbox-system rollout status deployment/opensandbox-server --timeout=120s
  if kubectl -n opensandbox-system get deployment opensandbox-demo >/dev/null 2>&1; then
    kubectl -n opensandbox-system rollout status deployment/opensandbox-demo --timeout=120s
  fi
  kubectl -n kube-federated-auth rollout status deployment/kube-federated-auth --timeout=120s
  echo "PASS: Kubernetes deployments"
fi

if [[ "$CHECK_KFA" == 1 ]]; then
  KFA_BASE_URL="$KFA_BASE_URL" "$ROOT_DIR/kfa-smoke.sh"
fi

CHECK_K8S="$CHECK_K8S" CHECK_PROMETHEUS="$CHECK_PROMETHEUS" \
  TENANT_SERVER_URL="$TENANT_SERVER_URL" \
  "$ROOT_DIR/tenant-server-smoke.sh"

echo "PASS: complete deployment smoke test"
