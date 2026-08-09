#!/usr/bin/env bash
set -euo pipefail

# Destructive only within a disposable test tenant: creates one sandbox,
# executes one command, uploads/downloads one file, then deletes everything.
# It does not delete existing tenants, sandboxes, or warm-pool pods.
#
# Run on cp-0 after the Tenant Server image and egress configuration are live:
#   TENANT_SERVER_URL=http://127.0.0.1:30081 \
#   CHECK_EGRESS=1 ./tenant-server-integration.sh

BASE_URL="${TENANT_SERVER_URL:-http://127.0.0.1:30081}"
ADMIN_TOKEN="${TENANT_SERVICEACCOUNT_ADMIN_TOKEN:-}"
CLIENT_TOKEN="${TENANT_SERVICEACCOUNT_TOKEN:-}"
CLIENT_NAMESPACE="${TENANT_NAMESPACE:-kfa-test}"
CLIENT_SERVICE_ACCOUNT="${TENANT_SERVICE_ACCOUNT:-kfa-test-client}"
POOL_REF="${OPENSANDBOX_POOL_REF:-python-warm-pool}"
SANDBOX_IMAGE="${OPENSANDBOX_IMAGE:-python:3.12-slim}"
EXEC_PORT="${OPENSANDBOX_EXEC_PORT:-44772}"
CHECK_EGRESS="${CHECK_EGRESS:-0}"
CHECK_K8S="${CHECK_K8S:-1}"
SANDBOX_CREATE_TIMEOUT="${SANDBOX_CREATE_TIMEOUT:-180}"
STAMP="$(date +%s)-$$"
TENANT_ID="integration-${STAMP}"
SANDBOX_ID=""
CLIENT_CREATED=0
TENANT_CREATED=0
TMP_DIR="$(mktemp -d)"

fail() { echo "FAIL: $*" >&2; exit 1; }
json() { curl --fail-with-body -sS --retry 3 --retry-delay 1 --retry-connrefused --max-time 30 "$@"; }
json_long() { curl --fail-with-body -sS --retry 3 --retry-delay 1 --retry-connrefused --max-time "$SANDBOX_CREATE_TIMEOUT" "$@"; }
cleanup() {
  if [[ -n "$SANDBOX_ID" && -n "$CLIENT_TOKEN" ]]; then
    curl -sS -X DELETE --max-time 30 -H "Authorization: Bearer $CLIENT_TOKEN" \
      "$BASE_URL/v1/sandboxes/$SANDBOX_ID" >/dev/null || true
  fi
  if [[ "$TENANT_CREATED" == 1 && -n "$ADMIN_TOKEN" ]]; then
    curl -sS -X DELETE --max-time 30 -H "Authorization: Bearer $ADMIN_TOKEN" \
      "$BASE_URL/admin/tenants/$TENANT_ID" >/dev/null || true
  fi
  if [[ "$CLIENT_CREATED" == 1 && "$CHECK_K8S" == 1 ]]; then
    kubectl -n "$CLIENT_NAMESPACE" delete serviceaccount "$CLIENT_SERVICE_ACCOUNT" --ignore-not-found=true >/dev/null || true
  fi
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

command -v curl >/dev/null || fail "curl is required"
command -v jq >/dev/null || fail "jq is required"
if [[ -z "$ADMIN_TOKEN" && "$CHECK_K8S" == 1 ]]; then
  ADMIN_TOKEN="$(kubectl -n opensandbox-tenant-server create token opensandbox-tenant-server --duration=10m)"
fi
if [[ -z "$CLIENT_TOKEN" && "$CHECK_K8S" == 1 ]]; then
  if [[ "$CLIENT_SERVICE_ACCOUNT" == kfa-test-client ]]; then
    CLIENT_SERVICE_ACCOUNT="integration-client-${STAMP}"
    kubectl -n "$CLIENT_NAMESPACE" create serviceaccount "$CLIENT_SERVICE_ACCOUNT" >/dev/null
    CLIENT_CREATED=1
  fi
  CLIENT_TOKEN="$(kubectl -n "$CLIENT_NAMESPACE" create token "$CLIENT_SERVICE_ACCOUNT" --duration=10m)"
fi
[[ -n "$ADMIN_TOKEN" && -n "$CLIENT_TOKEN" ]] || fail "admin and client ServiceAccount tokens are required"

created="$(json -X POST "$BASE_URL/admin/tenants" \
  -H "Authorization: Bearer $ADMIN_TOKEN" -H 'Content-Type: application/json' \
  -d "$(jq -nc --arg id "$TENANT_ID" --arg ns "$CLIENT_NAMESPACE" --arg sa "$CLIENT_SERVICE_ACCOUNT" --argjson scopes '["sandbox:create","sandbox:read","sandbox:delete","sandbox:command","sandbox:files","sandbox:egress"]' '{tenant_id:$id,cluster_name:"local-cluster",namespace:$ns,service_account:$sa,scopes:$scopes,max_concurrent_sandboxes:1}')")"
[[ "$(jq -r .tenant_id <<<"$created")" == "$TENANT_ID" ]] || fail "tenant creation: $created"
TENANT_CREATED=1

request="$(json_long -X POST "$BASE_URL/v1/sandboxes" \
  -H "Authorization: Bearer $CLIENT_TOKEN" -H 'Content-Type: application/json' \
  -d "$(jq -nc --arg pool "$POOL_REF" --arg image "$SANDBOX_IMAGE" '{image:{uri:$image},timeout:120,extensions:{poolRef:$pool},metadata:{source:"tenant-server-integration"}}')")" \
  || fail "sandbox create failed"
SANDBOX_ID="$(jq -r .id <<<"$request")"
[[ -n "$SANDBOX_ID" && "$SANDBOX_ID" != null ]] || fail "sandbox ID missing: $request"

command_response="$(curl -fsS --retry 2 --retry-delay 2 --max-time 60 \
  -X POST "$BASE_URL/v1/sandboxes/$SANDBOX_ID/proxy/$EXEC_PORT/command" \
  -H "Authorization: Bearer $CLIENT_TOKEN" -H 'Content-Type: application/json' \
  -d '{"command":"python -c \"print(\\\"tenant-integration-ok\\\")\"","cwd":"/workspace","background":false,"timeout":30000}' \
  || true)"
grep -q 'tenant-integration-ok' <<<"$command_response" || fail "command response did not contain expected output"

printf 'tenant-server-upload-ok\n' >"$TMP_DIR/input.txt"
curl -fsS --max-time 60 -X POST \
  "$BASE_URL/v1/sandboxes/$SANDBOX_ID/proxy/$EXEC_PORT/files/upload" \
  -H "Authorization: Bearer $CLIENT_TOKEN" \
  -F 'metadata={"path":"/workspace/input.txt","mode":600};type=application/json' \
  -F "file=@$TMP_DIR/input.txt;type=text/plain" >/dev/null

curl -fsS --max-time 60 \
  "$BASE_URL/v1/sandboxes/$SANDBOX_ID/proxy/$EXEC_PORT/files/download?path=/workspace/input.txt" \
  -H "Authorization: Bearer $CLIENT_TOKEN" -o "$TMP_DIR/output.txt"
cmp -s "$TMP_DIR/input.txt" "$TMP_DIR/output.txt" || fail "downloaded file differs from uploaded file"

if [[ "$CHECK_EGRESS" == 1 ]]; then
  egress="$(json -X PATCH "$BASE_URL/v1/sandboxes/$SANDBOX_ID/egress" \
    -H "Authorization: Bearer $CLIENT_TOKEN" -H 'Content-Type: application/json' \
    -d '{"action":"allow","target":"example.com"}')" || fail "egress allow failed"
  test -n "$egress"
fi

echo "PASS: Tenant Server integration test tenant=$TENANT_ID sandbox=$SANDBOX_ID"
