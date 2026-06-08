#!/usr/bin/env bash
set -euo pipefail
KUBECONFIG_PATH="$1"
agent_ready="$(kubectl --kubeconfig "$KUBECONFIG_PATH" -n agent-sandbox-system get deploy agent-sandbox-controller -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)"
openshell_ready="$(kubectl --kubeconfig "$KUBECONFIG_PATH" -n openshell get statefulset openshell -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)"
svc_type="$(kubectl --kubeconfig "$KUBECONFIG_PATH" -n openshell get svc openshell -o jsonpath='{.spec.type}' 2>/dev/null || echo none)"
if [[ "$agent_ready" -ge 1 && "$openshell_ready" -ge 1 && "$svc_type" != "none" ]]; then
  jq -n --arg svc "$svc_type" '{status:"pass",summary:("OpenShell control plane ready via service type " + $svc),details:{serviceType:$svc}}'
else
  jq -n --arg agent "$agent_ready" --arg shell "$openshell_ready" --arg svc "$svc_type" '{status:"fail",summary:"OpenShell control plane not fully ready",details:{agentReadyReplicas:($agent|tonumber),openshellReadyReplicas:($shell|tonumber),serviceType:$svc}}'
fi
