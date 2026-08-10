#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
VALUES="$ROOT_DIR/k8s/postgresql-bitnami-values.yaml"

test -f "$VALUES"
grep -q '^architecture: standalone$' "$VALUES"
grep -q 'existingSecret: opensandbox-tenant-server-postgres-auth' "$VALUES"
grep -q 'storageClass: local-path' "$VALUES"
grep -q 'size: 1Gi' "$VALUES"
grep -q '^    type: ClusterIP$' "$VALUES"
if grep -Eiq 'cloudnative|cnpg|postgresql\.cnpg\.io' "$VALUES"; then
  echo "FAIL: Bitnami values contain legacy operator settings" >&2
  exit 1
fi
echo "PASS: Bitnami PostgreSQL values"
