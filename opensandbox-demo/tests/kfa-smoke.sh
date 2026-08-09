#!/usr/bin/env bash
set -euo pipefail

# Run this script on cp-0, where kubectl is configured for the lab cluster.
KFA_BASE_URL="${KFA_BASE_URL:-http://10.10.0.48:30082}"

curl -fsS --max-time 10 "$KFA_BASE_URL/health" >/dev/null

target_token="$(kubectl -n kfa-test create token kfa-test-client --duration=10m)"
caller_token="$(kubectl -n opensandbox-tenant-server create token opensandbox-tenant-server --duration=10m)"
unauthorized_token="$(kubectl -n default create token default --duration=10m)"

review_body="$(jq -nc --arg token "$target_token" \
  '{apiVersion:"authentication.k8s.io/v1",kind:"TokenReview",spec:{token:$token}}')"

authorized_response="$(curl -fsS --max-time 20 \
  -X POST "$KFA_BASE_URL/apis/authentication.k8s.io/v1/tokenreviews" \
  -H "Authorization: Bearer $caller_token" \
  -H 'Content-Type: application/json' \
  --data "$review_body")"

test "$(printf '%s' "$authorized_response" | jq -r '.status.authenticated')" = true
test "$(printf '%s' "$authorized_response" | jq -r '.status.user.username')" = \
  'system:serviceaccount:kfa-test:kfa-test-client'
test "$(printf '%s' "$authorized_response" | jq -r '.status.user.extra["authentication.kubernetes.io/cluster-name"][0]')" = \
  local-cluster

unauthorized_status="$(curl -sS --max-time 20 -o /tmp/kfa-unauthorized.json -w '%{http_code}' \
  -X POST "$KFA_BASE_URL/apis/authentication.k8s.io/v1/tokenreviews" \
  -H "Authorization: Bearer $unauthorized_token" \
  -H 'Content-Type: application/json' \
  --data "$review_body")"
test "$unauthorized_status" = 403
test "$(jq -r '.status.error' /tmp/kfa-unauthorized.json)" = 'caller is not authorized'

echo "kube-federated-auth smoke test: PASS"
