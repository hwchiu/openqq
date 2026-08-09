#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
INGRESS="$ROOT_DIR/k8s/tenant-server-ingress.yaml"
command -v yq >/dev/null || { echo "yq is required" >&2; exit 2; }

yq -e '
  .kind == "Ingress" and
  .spec.ingressClassName == "nginx" and
  .spec.tls[0].secretName == "opensandbox-tenant-server-tls" and
  .metadata.annotations."nginx.ingress.kubernetes.io/force-ssl-redirect" == "true" and
  .metadata.annotations."nginx.ingress.kubernetes.io/proxy-body-size" == "50m" and
  .metadata.annotations."nginx.ingress.kubernetes.io/proxy-request-buffering" == "off" and
  .metadata.annotations."nginx.ingress.kubernetes.io/proxy-buffering" == "off" and
  .metadata.annotations."nginx.ingress.kubernetes.io/proxy-read-timeout" == "3600" and
  .spec.rules[0].http.paths[0].backend.service.name == "opensandbox-tenant-server" and
  .spec.rules[0].http.paths[0].backend.service.port.number == 8080
' "$INGRESS" >/dev/null
if yq -e '.. | select(has("name")) | .name == "opensandbox-server"' "$INGRESS" >/dev/null 2>&1; then
  echo "FAIL: ingress exposes OpenSandbox directly" >&2
  exit 1
fi
echo "PASS: Tenant Server HTTPS ingress render"
