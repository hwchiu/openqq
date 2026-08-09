#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
command -v kubectl >/dev/null || { echo "kubectl is required" >&2; exit 2; }

rendered=$(kubectl kustomize --load-restrictor=LoadRestrictionsNone "$ROOT_DIR/k8s/overlays/postgres-backup")
grep -q 'kind: ScheduledBackup' <<<"$rendered"
grep -q 'schedule: 0 \*/15 \* \* \* \*' <<<"$rendered"
grep -q 'method: barmanObjectStore' <<<"$rendered"
grep -q 'retentionPolicy: 30d' <<<"$rendered"
grep -q 'destinationPath: s3://REPLACE_BUCKET/' <<<"$rendered"
grep -q 'name: opensandbox-postgres-backup' <<<"$rendered"
if grep -Eq 'AKIA|accessKeyId: [^n]|secretAccessKey: [^n]' <<<"$rendered"; then
  echo "FAIL: backup render contains a concrete credential" >&2
  exit 1
fi
echo "PASS: PostgreSQL backup overlay render"
