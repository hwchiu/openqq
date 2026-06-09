#!/usr/bin/env bash
set -euo pipefail

KUBECONFIG_PATH="$1"
namespace="${ISTIO_NAMESPACE:-istio-system}"

ready="$(kubectl --kubeconfig "$KUBECONFIG_PATH" -n "$namespace" get deploy istiod -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)"
chart="$(helm --kubeconfig "$KUBECONFIG_PATH" -n "$namespace" ls -o json 2>/dev/null | jq -r '.[] | select(.name=="istiod") | .chart' | head -n1)"

if [[ "${ready:-0}" -ge 1 ]]; then
  jq -n --arg chart "${chart:-unknown}" '{status:"pass",summary:("Istio control plane ready (" + $chart + ")"),details:{chart:$chart}}'
else
  jq -n --arg ready "${ready:-0}" '{status:"fail",summary:"Istio control plane not ready",details:{readyReplicas:($ready|tonumber)}}'
fi
