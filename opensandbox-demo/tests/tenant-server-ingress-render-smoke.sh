#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
INGRESS="$ROOT_DIR/k8s/tenant-server-ingress.yaml"
command -v ruby >/dev/null || { echo "ruby is required" >&2; exit 2; }

ruby -ryaml -e '
  d = YAML.load_file(ARGV.fetch(0))
  a = d.fetch("metadata").fetch("annotations")
  path = d.fetch("spec").fetch("rules").fetch(0).fetch("http").fetch("paths").fetch(0)
  service = path.fetch("backend").fetch("service")
  checks = [
    d["kind"] == "Ingress",
    d.dig("spec", "ingressClassName") == "nginx",
    d.dig("spec", "tls", 0, "secretName") == "opensandbox-tenant-server-tls",
    a["nginx.ingress.kubernetes.io/force-ssl-redirect"] == "true",
    a["nginx.ingress.kubernetes.io/proxy-body-size"] == "50m",
    a["nginx.ingress.kubernetes.io/proxy-request-buffering"] == "off",
    a["nginx.ingress.kubernetes.io/proxy-buffering"] == "off",
    a["nginx.ingress.kubernetes.io/proxy-read-timeout"] == "3600",
    service["name"] == "opensandbox-tenant-server",
    service.dig("port", "number") == 8080
  ]
  abort "invalid Tenant Server ingress" unless checks.all?
  abort "OpenSandbox service is exposed directly" if d.to_s.include?("opensandbox-server")
' "$INGRESS"
if grep -q 'name: opensandbox-server' "$INGRESS"; then
  echo "FAIL: ingress exposes OpenSandbox directly" >&2
  exit 1
fi
echo "PASS: Tenant Server HTTPS ingress render"
