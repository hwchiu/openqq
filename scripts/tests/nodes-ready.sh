#!/usr/bin/env bash
set -euo pipefail
KUBECONFIG_PATH="$1"
json="$(kubectl --kubeconfig "$KUBECONFIG_PATH" get nodes -o json)"
count="$(jq '.items | length' <<<"$json")"
ready="$(jq '[.items[] | any(.status.conditions[]; .type=="Ready" and .status=="True")] | all' <<<"$json")"
if [[ "$count" -eq 3 && "$ready" == "true" ]]; then
  jq -n --arg count "$count" '{status:"pass",summary:("3-node cluster healthy (" + $count + " nodes Ready)"),details:{nodeCount:($count|tonumber)}}'
else
  jq -n --arg count "$count" --argjson ready "$ready" '{status:"fail",summary:("Expected 3 Ready nodes; observed " + $count),details:{nodeCount:($count|tonumber),allReady:$ready}}'
fi
