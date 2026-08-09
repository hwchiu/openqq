#!/usr/bin/env bash
set -euo pipefail

# Repeatable contract test. Run on a cluster node, or provide a reachable URL:
#   TENANT_SERVER_URL=http://10.10.0.154:30081 ./tenant-server-smoke.sh
# Required tools: curl, jq, kubectl only when CHECK_K8S=1.

BASE_URL="${TENANT_SERVER_URL:-http://127.0.0.1:18080}"
ADMIN_TOKEN="${TENANT_SERVER_ADMIN_TOKEN:-}"
CHECK_K8S="${CHECK_K8S:-0}"
STAMP="$(date +%s)-$$"
TENANT_ID="smoke-${STAMP}"

fail() { echo "FAIL: $*" >&2; exit 1; }
json() { curl -fsS --max-time 15 "$@"; }

if [[ -z "$ADMIN_TOKEN" ]]; then
  if [[ "$CHECK_K8S" == 1 ]]; then
    ADMIN_TOKEN="$(kubectl -n opensandbox-tenant-server get secret opensandbox-tenant-server-secrets -o jsonpath='{.data.admin-token}' | base64 -d)"
  else
    fail "set TENANT_SERVER_ADMIN_TOKEN or run with CHECK_K8S=1"
  fi
fi

health="$(json "$BASE_URL/health")"
[[ "$(jq -r .status <<<"$health")" == ok ]] || fail "health: $health"
[[ "$(jq -r .store <<<"$health")" == postgres ]] || fail "unexpected store: $health"

metrics="$(json "$BASE_URL/metrics")"
grep -q '^opensandbox_tenant_server_requests_total' <<<"$metrics" || fail "tenant request metric missing"

unauth_status="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 15 "$BASE_URL/v1/sandboxes")"
[[ "$unauth_status" == 401 ]] || fail "unauthenticated request returned $unauth_status"

created="$(json -X POST "$BASE_URL/admin/tenants" \
  -H "X-Tenant-Server-Admin-Token: $ADMIN_TOKEN" \
  -H 'Content-Type: application/json' \
  -d "{\"tenant_id\":\"$TENANT_ID\",\"max_concurrent_sandboxes\":1}")"
TENANT_KEY="$(jq -r .tenant_key <<<"$created")"
[[ -n "$TENANT_KEY" && "$TENANT_KEY" != null ]] || fail "tenant creation: $created"

listed="$(json -H "X-Tenant-Server-Admin-Token: $ADMIN_TOKEN" "$BASE_URL/admin/tenants")"
grep -q "\"tenant_id\":\"$TENANT_ID\"" <<<"$listed" || fail "tenant missing from admin list"

snapshot_status="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 15 \
  -H "Authorization: Bearer $TENANT_KEY" "$BASE_URL/v1/snapshots")"
[[ "$snapshot_status" == 404 ]] || fail "snapshot route returned $snapshot_status"

disabled="$(json -X DELETE -H "X-Tenant-Server-Admin-Token: $ADMIN_TOKEN" \
  "$BASE_URL/admin/tenants/$TENANT_ID")"
[[ "$(jq -r .enabled <<<"$disabled")" == false ]] || fail "tenant disable: $disabled"

disabled_status="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 15 \
  -H "Authorization: Bearer $TENANT_KEY" "$BASE_URL/v1/sandboxes")"
[[ "$disabled_status" == 401 || "$disabled_status" == 403 ]] || fail "disabled tenant returned $disabled_status"

echo "PASS: Tenant Server smoke test ($TENANT_ID)"
