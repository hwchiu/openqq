#!/usr/bin/env bash
set -euo pipefail

# Repeatable contract test. Run on a cluster node, or provide a reachable URL:
#   TENANT_SERVER_URL=http://10.10.0.154:30081 ./tenant-server-smoke.sh
# Required tools: curl, jq, kubectl only when CHECK_K8S=1.

BASE_URL="${TENANT_SERVER_URL:-http://127.0.0.1:18080}"
ADMIN_TOKEN="${TENANT_SERVICEACCOUNT_ADMIN_TOKEN:-}"
CHECK_K8S="${CHECK_K8S:-0}"
CHECK_PROMETHEUS="${CHECK_PROMETHEUS:-0}"
STAMP="$(date +%s)-$$"
TENANT_ID="smoke-${STAMP}"
CLIENT_TOKEN="${TENANT_SERVICEACCOUNT_TOKEN:-}"
CLIENT_NAMESPACE="${TENANT_NAMESPACE:-kfa-test}"
CLIENT_SERVICE_ACCOUNT="${TENANT_SERVICE_ACCOUNT:-kfa-test-client}"
CREATED=0
CLIENT_CREATED=0

fail() { echo "FAIL: $*" >&2; exit 1; }
json() { curl -fsS --retry 4 --retry-delay 1 --retry-connrefused --max-time 15 "$@"; }
cleanup() {
  if [[ "$CREATED" == 1 ]]; then
    curl -sS -X DELETE --max-time 15 \
      -H "Authorization: Bearer $ADMIN_TOKEN" \
      "$BASE_URL/admin/tenants/$TENANT_ID" >/dev/null || true
  fi
  if [[ "$CLIENT_CREATED" == 1 ]]; then
    kubectl -n "$CLIENT_NAMESPACE" delete serviceaccount "$CLIENT_SERVICE_ACCOUNT" --ignore-not-found=true >/dev/null || true
  fi
}
trap cleanup EXIT

if [[ -z "$ADMIN_TOKEN" ]]; then
  if [[ "$CHECK_K8S" == 1 ]]; then
    ADMIN_TOKEN="$(kubectl -n opensandbox-tenant-server create token opensandbox-tenant-server --duration=10m)"
  else
    fail "set TENANT_SERVICEACCOUNT_ADMIN_TOKEN or run with CHECK_K8S=1"
  fi
fi

if [[ -z "$CLIENT_TOKEN" && "$CHECK_K8S" == 1 ]]; then
  if [[ "$CLIENT_SERVICE_ACCOUNT" == kfa-test-client ]]; then
    CLIENT_SERVICE_ACCOUNT="smoke-client-${STAMP}"
    kubectl -n "$CLIENT_NAMESPACE" create serviceaccount "$CLIENT_SERVICE_ACCOUNT" >/dev/null
    CLIENT_CREATED=1
  fi
  CLIENT_TOKEN="$(kubectl -n "$CLIENT_NAMESPACE" create token "$CLIENT_SERVICE_ACCOUNT" --duration=10m)"
fi
[[ -n "$CLIENT_TOKEN" ]] || fail "set TENANT_SERVICEACCOUNT_TOKEN or run with CHECK_K8S=1"

health="$(json "$BASE_URL/health")"
[[ "$(jq -r .status <<<"$health")" == ok ]] || fail "health: $health"
[[ "$(jq -r .store <<<"$health")" == postgres ]] || fail "unexpected store: $health"

if [[ "$CHECK_K8S" == 1 ]]; then
  ready="$(kubectl -n opensandbox-tenant-server get deployment opensandbox-tenant-server -o jsonpath='{.status.readyReplicas}')"
  [[ "$ready" == 3 ]] || fail "expected 3 Ready replicas, got ${ready:-0}"
  while read -r ip; do
    [[ -z "$ip" ]] && continue
    node_health="$(json "http://$ip:18080/health")"
    [[ "$(jq -r .status <<<"$node_health")" == ok ]] || fail "node $ip health: $node_health"
  done < <(kubectl get nodes -o json | jq -r '.items[].status.addresses[] | select(.type == "InternalIP") | .address')
fi

metrics="$(json "$BASE_URL/metrics")"
grep -q '^opensandbox_tenant_server_requests_total' <<<"$metrics" || fail "tenant request metric missing"

unauth_status="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 15 "$BASE_URL/v1/sandboxes")"
[[ "$unauth_status" == 401 ]] || fail "unauthenticated request returned $unauth_status"

created="$(json -X POST "$BASE_URL/admin/tenants" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H 'Content-Type: application/json' \
  -d "{\"tenant_id\":\"$TENANT_ID\",\"cluster_name\":\"local-cluster\",\"namespace\":\"$CLIENT_NAMESPACE\",\"service_account\":\"$CLIENT_SERVICE_ACCOUNT\",\"max_concurrent_sandboxes\":1}")"
[[ "$(jq -r .service_account <<<"$created")" == "$CLIENT_SERVICE_ACCOUNT" ]] || fail "tenant creation: $created"
CREATED=1

listed="$(json -H "Authorization: Bearer $ADMIN_TOKEN" "$BASE_URL/admin/tenants")"
jq -e --arg id "$TENANT_ID" 'any(.[]; .tenant_id == $id)' <<<"$listed" >/dev/null || fail "tenant missing from admin list"

snapshot_status="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 15 \
  -H "Authorization: Bearer $CLIENT_TOKEN" "$BASE_URL/v1/snapshots")"
[[ "$snapshot_status" == 404 ]] || fail "snapshot route returned $snapshot_status"

# `/v1/snapshots` is rejected before authentication by design. Exercise an
# authenticated allowlisted route separately; upstream availability is not
# part of this smoke test, so 200/4xx/502 are all acceptable here.
curl -sS -o /dev/null --max-time 15 \
  -H "Authorization: Bearer $CLIENT_TOKEN" "$BASE_URL/v1/sandboxes" || true

metrics_after="$(json "$BASE_URL/metrics")"
grep -q "tenant=\"$TENANT_ID\"" <<<"$metrics_after" || fail "tenant label missing from metrics"

disabled="$(json -X DELETE -H "Authorization: Bearer $ADMIN_TOKEN" \
  "$BASE_URL/admin/tenants/$TENANT_ID")"
[[ "$(jq -r .enabled <<<"$disabled")" == false ]] || fail "tenant disable: $disabled"

disabled_status="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 15 \
  -H "Authorization: Bearer $CLIENT_TOKEN" "$BASE_URL/v1/sandboxes")"
[[ "$disabled_status" == 401 || "$disabled_status" == 403 ]] || fail "disabled tenant returned $disabled_status"

if [[ "$CHECK_PROMETHEUS" == 1 ]]; then
  PF_LOG="$(mktemp)"
  kubectl -n monitoring port-forward svc/monitoring-kube-prometheus-prometheus 19090:9090 >"$PF_LOG" 2>&1 &
  PF_PID=$!
  trap 'kill "$PF_PID" 2>/dev/null || true; rm -f "$PF_LOG"; cleanup' EXIT
  for _ in {1..15}; do
    if curl -fsS --max-time 1 http://127.0.0.1:19090/-/ready >/dev/null 2>&1; then break; fi
    sleep 1
  done
  prom="$(curl -fsS --get --max-time 10 http://127.0.0.1:19090/api/v1/query \
    --data-urlencode 'query=up{job="opensandbox-tenant-server"}')"
  [[ "$(jq '[.data.result[] | select(.value[1] == "1")] | length' <<<"$prom")" == 3 ]] || fail "Prometheus does not see 3 healthy Tenant Server targets"
fi

echo "PASS: Tenant Server smoke test ($TENANT_ID)"
