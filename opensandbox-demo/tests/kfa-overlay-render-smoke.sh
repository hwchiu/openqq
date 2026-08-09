#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
command -v kubectl >/dev/null || { echo "kubectl is required" >&2; exit 2; }

rendered=$(kubectl kustomize --load-restrictor=LoadRestrictionsNone "$ROOT_DIR/k8s/overlays/production")
grep -q '^  replicas: 3$' <<<"$rendered"
grep -q '^  type: ClusterIP$' <<<"$rendered"
grep -q '^kind: PodDisruptionBudget$' <<<"$rendered"
if grep -q '^      hostNetwork: true$' <<<"$rendered"; then
  echo "FAIL: production KFA overlay still enables hostNetwork" >&2
  exit 1
fi
if grep -q '^    nodePort:' <<<"$rendered"; then
  echo "FAIL: production KFA overlay still exposes a NodePort" >&2
  exit 1
fi
echo "PASS: KFA production overlay render"
