#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ALERTS="$ROOT_DIR/k8s/tenant-server-alerts.yaml"

command -v jq >/dev/null || { echo "FAIL: jq is required" >&2; exit 1; }

# PrometheusRule is a CRD. Keep this check independent of a live API server;
# the explicit structural checks prevent a rule file from silently losing the
# tenant-server alert groups.
grep -q '^apiVersion: monitoring.coreos.com/v1$' "$ALERTS"
grep -q '^kind: PrometheusRule$' "$ALERTS"
grep -q '^    release: monitoring$' "$ALERTS"
for alert in \
  TenantServerReplicaUnavailable \
  TenantServerTargetDown \
  TenantServerAuthenticationFailures \
  TenantServerQuotaRejections \
  TenantServerUpstreamErrors \
  TenantServerEgressFailures; do
  grep -q "alert: $alert" "$ALERTS" || { echo "FAIL: missing alert $alert" >&2; exit 1; }
done

jq empty "$ROOT_DIR/k8s/tenant-server-dashboard.json"
jq empty "$ROOT_DIR/k8s/opensandbox-dashboard.json"
grep -q 'opensandbox_tenant_server_requests_total' "$ROOT_DIR/k8s/tenant-server-dashboard.json"
grep -q 'opensandbox_tenant_server_egress_operations_total' "$ROOT_DIR/k8s/tenant-server-dashboard.json"

echo "PASS: Tenant Server alert and dashboard render"
