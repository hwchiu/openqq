#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KUBECONFIG_PATH="${KUBECONFIG_PATH:-$ROOT_DIR/generated/kubeconfig}"
GATEWAY_ENDPOINT="${GATEWAY_ENDPOINT:-$("$ROOT_DIR/scripts/get-openshell-endpoint.sh")}"
SANDBOX_NAME="${SANDBOX_NAME:-verify-$(date +%s)}"
WORK_DIR="$ROOT_DIR/testing/raw/$SANDBOX_NAME"

mkdir -p "$WORK_DIR"

cleanup() {
  if [[ -n "${CREATE_PID:-}" ]]; then
    kill "$CREATE_PID" >/dev/null 2>&1 || true
    wait "$CREATE_PID" 2>/dev/null || true
  fi
  openshell --gateway-endpoint "$GATEWAY_ENDPOINT" sandbox delete "$SANDBOX_NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

openshell --gateway-endpoint "$GATEWAY_ENDPOINT" sandbox create \
  --name "$SANDBOX_NAME" \
  --no-auto-providers \
  --no-tty \
  -- sleep infinity >/tmp/"$SANDBOX_NAME".create.log 2>&1 &
CREATE_PID=$!
sleep 2

kubectl --kubeconfig "$KUBECONFIG_PATH" -n openshell wait --for=jsonpath='{.status.conditions[0].status}'=True sandbox/"$SANDBOX_NAME" --timeout=300s

openshell --gateway-endpoint "$GATEWAY_ENDPOINT" sandbox exec -n "$SANDBOX_NAME" -- /bin/sh -lc 'id && pwd && ls /' \
  > "$WORK_DIR/static-baseline.txt" 2>&1 || true

openshell --gateway-endpoint "$GATEWAY_ENDPOINT" sandbox exec -n "$SANDBOX_NAME" -- /bin/sh -lc 'touch /tmp/verify-ok && echo TMP_OK && touch /var/tmp/verify-deny && echo VARTMP_OK || echo VARTMP_DENIED' \
  > "$WORK_DIR/filesystem.txt" 2>&1 || true

openshell --gateway-endpoint "$GATEWAY_ENDPOINT" sandbox exec -n "$SANDBOX_NAME" -- /bin/sh -lc 'curl -sS https://api.github.com/zen' \
  > "$WORK_DIR/default-egress.txt" 2>&1 || true

cat > "$WORK_DIR/github-readonly.yaml" <<'EOF'
version: 1
filesystem_policy:
  include_workdir: true
  read_only: [/usr, /lib, /proc, /dev/urandom, /app, /etc, /var/log]
  read_write: [/sandbox, /tmp, /dev/null]
landlock:
  compatibility: best_effort
process:
  run_as_user: sandbox
  run_as_group: sandbox
network_policies:
  github_api:
    name: github-api-readonly
    endpoints:
      - host: api.github.com
        port: 443
        protocol: rest
        enforcement: enforce
        access: read-only
    binaries:
      - path: /usr/bin/curl
EOF

before_uid="$(kubectl --kubeconfig "$KUBECONFIG_PATH" -n openshell get pod "$SANDBOX_NAME" -o jsonpath='{.metadata.uid}')"
printf '%s\n' "$before_uid" > "$WORK_DIR/pod_uid_before.txt"
openshell --gateway-endpoint "$GATEWAY_ENDPOINT" policy set "$SANDBOX_NAME" --policy "$WORK_DIR/github-readonly.yaml" --wait > "$WORK_DIR/policy-set.txt"
after_uid="$(kubectl --kubeconfig "$KUBECONFIG_PATH" -n openshell get pod "$SANDBOX_NAME" -o jsonpath='{.metadata.uid}')"
printf '%s\n' "$after_uid" > "$WORK_DIR/pod_uid_after.txt"

openshell --gateway-endpoint "$GATEWAY_ENDPOINT" sandbox exec -n "$SANDBOX_NAME" -- /bin/sh -lc 'curl -sS https://api.github.com/zen' \
  > "$WORK_DIR/curl-get.txt" 2>&1 || true

openshell --gateway-endpoint "$GATEWAY_ENDPOINT" sandbox exec -n "$SANDBOX_NAME" -- /bin/sh -lc "python3 -c \"import urllib.request; print(urllib.request.urlopen('https://api.github.com/zen', timeout=10).read().decode())\"" \
  > "$WORK_DIR/python-get.txt" 2>&1 || true

openshell --gateway-endpoint "$GATEWAY_ENDPOINT" sandbox exec -n "$SANDBOX_NAME" -- /bin/sh -lc "curl -sS -X POST https://api.github.com/repos/octocat/hello-world/issues -d '{\"title\":\"verify\"}'" \
  > "$WORK_DIR/curl-post.txt" 2>&1 || true

openshell --gateway-endpoint "$GATEWAY_ENDPOINT" logs "$SANDBOX_NAME" --since 10m --source sandbox > "$WORK_DIR/sandbox-logs.txt" || true

printf 'evidence written to %s\n' "$WORK_DIR"
