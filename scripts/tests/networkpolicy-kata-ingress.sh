#!/usr/bin/env bash
set -euo pipefail

KUBECONFIG_PATH="$1"
STACK_NAME="${2:-unknown}"
SUFFIX="$(date +%s)"
NS="np-kata-${SUFFIX}"
SERVER="server"
ALLOWED="allowed"
BLOCKED="blocked"
SVC="server"
ROLLOUT_TIMEOUT="${ROLLOUT_TIMEOUT:-300s}"
POLICY_SETTLE_SECONDS="${POLICY_SETTLE_SECONDS:-20}"
KEEP_NAMESPACE="${KEEP_NAMESPACE:-false}"
WORK_DIR="$(mktemp -d)"
WAIT_ERR="$WORK_DIR/wait.err"
BLOCKED_STDOUT="$WORK_DIR/blocked.stdout"
BLOCKED_STDERR="$WORK_DIR/blocked.stderr"

cleanup() {
  if [[ "$KEEP_NAMESPACE" != "true" ]]; then
    kubectl --kubeconfig "$KUBECONFIG_PATH" delete ns "$NS" --ignore-not-found --wait=false >/dev/null 2>&1 || true
  fi
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 1; }

kubectl --kubeconfig "$KUBECONFIG_PATH" get runtimeclass kata >/dev/null

cat <<YAML | kubectl --kubeconfig "$KUBECONFIG_PATH" apply -f - >/dev/null
apiVersion: v1
kind: Namespace
metadata:
  name: ${NS}
---
apiVersion: v1
kind: Pod
metadata:
  name: ${SERVER}
  namespace: ${NS}
  labels:
    app: server
spec:
  runtimeClassName: kata
  containers:
    - name: server
      image: hashicorp/http-echo:1.0.0
      args: ["-text=np-ok"]
      ports:
        - containerPort: 5678
---
apiVersion: v1
kind: Service
metadata:
  name: ${SVC}
  namespace: ${NS}
spec:
  selector:
    app: server
  ports:
    - port: 80
      targetPort: 5678
---
apiVersion: v1
kind: Pod
metadata:
  name: ${ALLOWED}
  namespace: ${NS}
  labels:
    access: allowed
spec:
  runtimeClassName: kata
  containers:
    - name: curl
      image: curlimages/curl:8.8.0
      command: ["/bin/sh", "-c", "sleep 365d"]
---
apiVersion: v1
kind: Pod
metadata:
  name: ${BLOCKED}
  namespace: ${NS}
spec:
  runtimeClassName: kata
  containers:
    - name: curl
      image: curlimages/curl:8.8.0
      command: ["/bin/sh", "-c", "sleep 365d"]
YAML

set +e
kubectl --kubeconfig "$KUBECONFIG_PATH" -n "$NS" wait --for=condition=Ready pod/"$SERVER" pod/"$ALLOWED" pod/"$BLOCKED" --timeout="$ROLLOUT_TIMEOUT" >/dev/null 2>"$WAIT_ERR"
wait_rc=$?
set -e

if [[ $wait_rc -ne 0 ]]; then
  pods="$(kubectl --kubeconfig "$KUBECONFIG_PATH" -n "$NS" get pods -o wide 2>&1 || true)"
  jq -n \
    --arg stack "$STACK_NAME" \
    --arg namespace "$NS" \
    --arg waitError "$(cat "$WAIT_ERR")" \
    --arg pods "$pods" \
    '{
      status:"fail",
      summary:"Kata network policy probe pods did not become Ready",
      details:{
        stack:$stack,
        namespace:$namespace,
        waitError:$waitError,
        pods:$pods
      }
    }'
  exit 0
fi

baseline_allowed="$(kubectl --kubeconfig "$KUBECONFIG_PATH" -n "$NS" exec "$ALLOWED" -- curl -fsS --max-time 5 "http://${SVC}.${NS}.svc.cluster.local/")"
baseline_blocked="$(kubectl --kubeconfig "$KUBECONFIG_PATH" -n "$NS" exec "$BLOCKED" -- curl -fsS --max-time 5 "http://${SVC}.${NS}.svc.cluster.local/")"

cat <<YAML | kubectl --kubeconfig "$KUBECONFIG_PATH" apply -f - >/dev/null
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-only-labeled
  namespace: ${NS}
spec:
  podSelector:
    matchLabels:
      app: server
  policyTypes:
    - Ingress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              access: allowed
YAML

allowed_after_policy=""
blocked_rc=0
for ((attempt=1; attempt<=POLICY_SETTLE_SECONDS; attempt++)); do
  allowed_after_policy="$(kubectl --kubeconfig "$KUBECONFIG_PATH" -n "$NS" exec "$ALLOWED" -- curl -fsS --max-time 5 "http://${SVC}.${NS}.svc.cluster.local/")"

  set +e
  kubectl --kubeconfig "$KUBECONFIG_PATH" -n "$NS" exec "$BLOCKED" -- curl -fsS --max-time 5 "http://${SVC}.${NS}.svc.cluster.local/" >"$BLOCKED_STDOUT" 2>"$BLOCKED_STDERR"
  blocked_rc=$?
  set -e

  if [[ "$allowed_after_policy" == "np-ok" && $blocked_rc -ne 0 ]]; then
    break
  fi

  sleep 1
done

server_runtime_class="$(kubectl --kubeconfig "$KUBECONFIG_PATH" -n "$NS" get pod "$SERVER" -o jsonpath='{.spec.runtimeClassName}')"
allowed_runtime_class="$(kubectl --kubeconfig "$KUBECONFIG_PATH" -n "$NS" get pod "$ALLOWED" -o jsonpath='{.spec.runtimeClassName}')"
blocked_runtime_class="$(kubectl --kubeconfig "$KUBECONFIG_PATH" -n "$NS" get pod "$BLOCKED" -o jsonpath='{.spec.runtimeClassName}')"
server_node="$(kubectl --kubeconfig "$KUBECONFIG_PATH" -n "$NS" get pod "$SERVER" -o jsonpath='{.spec.nodeName}')"
allowed_node="$(kubectl --kubeconfig "$KUBECONFIG_PATH" -n "$NS" get pod "$ALLOWED" -o jsonpath='{.spec.nodeName}')"
blocked_node="$(kubectl --kubeconfig "$KUBECONFIG_PATH" -n "$NS" get pod "$BLOCKED" -o jsonpath='{.spec.nodeName}')"
blocked_stdout="$(cat "$BLOCKED_STDOUT" 2>/dev/null || true)"
blocked_stderr="$(cat "$BLOCKED_STDERR" 2>/dev/null || true)"

if [[ "$baseline_allowed" == "np-ok" && "$baseline_blocked" == "np-ok" && "$allowed_after_policy" == "np-ok" && $blocked_rc -ne 0 ]]; then
  jq -n \
    --arg stack "$STACK_NAME" \
    --arg namespace "$NS" \
    --arg baselineAllowed "$baseline_allowed" \
    --arg baselineBlocked "$baseline_blocked" \
    --arg allowedAfterPolicy "$allowed_after_policy" \
    --arg blockedStdout "$blocked_stdout" \
    --arg blockedStderr "$blocked_stderr" \
    --arg serverNode "$server_node" \
    --arg allowedNode "$allowed_node" \
    --arg blockedNode "$blocked_node" \
    --arg serverRuntimeClass "$server_runtime_class" \
    --arg allowedRuntimeClass "$allowed_runtime_class" \
    --arg blockedRuntimeClass "$blocked_runtime_class" \
    --argjson blockedExitCode "$blocked_rc" \
    '{
      status:"pass",
      summary:"Kata ingress NetworkPolicy allowed labeled traffic and blocked unlabeled traffic",
      details:{
        stack:$stack,
        namespace:$namespace,
        baselineAllowed:$baselineAllowed,
        baselineBlocked:$baselineBlocked,
        allowedAfterPolicy:$allowedAfterPolicy,
        blockedExitCode:$blockedExitCode,
        blockedStdout:$blockedStdout,
        blockedStderr:$blockedStderr,
        serverNode:$serverNode,
        allowedNode:$allowedNode,
        blockedNode:$blockedNode,
        serverRuntimeClass:$serverRuntimeClass,
        allowedRuntimeClass:$allowedRuntimeClass,
        blockedRuntimeClass:$blockedRuntimeClass
      }
    }'
else
  jq -n \
    --arg stack "$STACK_NAME" \
    --arg namespace "$NS" \
    --arg baselineAllowed "$baseline_allowed" \
    --arg baselineBlocked "$baseline_blocked" \
    --arg allowedAfterPolicy "$allowed_after_policy" \
    --arg blockedStdout "$blocked_stdout" \
    --arg blockedStderr "$blocked_stderr" \
    --arg serverNode "$server_node" \
    --arg allowedNode "$allowed_node" \
    --arg blockedNode "$blocked_node" \
    --arg serverRuntimeClass "$server_runtime_class" \
    --arg allowedRuntimeClass "$allowed_runtime_class" \
    --arg blockedRuntimeClass "$blocked_runtime_class" \
    --argjson blockedExitCode "$blocked_rc" \
    '{
      status:"fail",
      summary:"Kata ingress NetworkPolicy smoke test failed",
      details:{
        stack:$stack,
        namespace:$namespace,
        baselineAllowed:$baselineAllowed,
        baselineBlocked:$baselineBlocked,
        allowedAfterPolicy:$allowedAfterPolicy,
        blockedExitCode:$blockedExitCode,
        blockedStdout:$blockedStdout,
        blockedStderr:$blockedStderr,
        serverNode:$serverNode,
        allowedNode:$allowedNode,
        blockedNode:$blockedNode,
        serverRuntimeClass:$serverRuntimeClass,
        allowedRuntimeClass:$allowedRuntimeClass,
        blockedRuntimeClass:$blockedRuntimeClass
      }
    }'
fi
