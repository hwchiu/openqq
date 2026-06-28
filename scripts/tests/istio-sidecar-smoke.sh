#!/usr/bin/env bash
set -euo pipefail

KUBECONFIG_PATH="$1"
STACK_NAME="${2:-unknown}"
SUFFIX="$(date +%s)"
RUNTIME_CLASS_NAME="${RUNTIME_CLASS_NAME:-}"
EXPECTED_RESPONSE="${EXPECTED_RESPONSE:-mesh-ok}"
NAMESPACE_PREFIX="${NAMESPACE_PREFIX:-istio-smoke}"
KEEP_NAMESPACE="${KEEP_NAMESPACE:-false}"
ROLLOUT_TIMEOUT="${ROLLOUT_TIMEOUT:-300s}"
NS="${NAMESPACE_PREFIX}-${SUFFIX}"
SERVER="echo-${SUFFIX}"
CLIENT="curl-${SUFFIX}"
SVC="echo"
WORK_DIR="$(mktemp -d)"
SERVER_ERR="$WORK_DIR/server.err"
CLIENT_ERR="$WORK_DIR/client.err"
CLIENT_CURL_ERR="$WORK_DIR/client-curl.err"

cleanup() {
  if [[ "$KEEP_NAMESPACE" != "true" ]]; then
    kubectl --kubeconfig "$KUBECONFIG_PATH" delete ns "$NS" --ignore-not-found --wait=false >/dev/null 2>&1 || true
  fi
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

runtime_class_snippet=""
if [[ -n "$RUNTIME_CLASS_NAME" ]]; then
  kubectl --kubeconfig "$KUBECONFIG_PATH" get runtimeclass "$RUNTIME_CLASS_NAME" >/dev/null
  runtime_class_snippet="      runtimeClassName: ${RUNTIME_CLASS_NAME}"
fi

cat <<YAML | kubectl --kubeconfig "$KUBECONFIG_PATH" apply -f - >/dev/null
apiVersion: v1
kind: Namespace
metadata:
  name: ${NS}
  labels:
    istio-injection: enabled
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${SERVER}
  namespace: ${NS}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ${SERVER}
  template:
    metadata:
      labels:
        app: ${SERVER}
    spec:
${runtime_class_snippet}
      containers:
        - name: echo
          image: hashicorp/http-echo:1.0.0
          args: ["-text=${EXPECTED_RESPONSE}"]
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
    app: ${SERVER}
  ports:
    - port: 80
      targetPort: 5678
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${CLIENT}
  namespace: ${NS}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ${CLIENT}
  template:
    metadata:
      labels:
        app: ${CLIENT}
    spec:
${runtime_class_snippet}
      containers:
        - name: curl
          image: curlimages/curl:8.8.0
          command: ["/bin/sh", "-c", "sleep 365d"]
YAML

set +e
kubectl --kubeconfig "$KUBECONFIG_PATH" -n "$NS" rollout status deploy/"$SERVER" --timeout="$ROLLOUT_TIMEOUT" >/dev/null 2>"$SERVER_ERR"
server_rc=$?
kubectl --kubeconfig "$KUBECONFIG_PATH" -n "$NS" rollout status deploy/"$CLIENT" --timeout="$ROLLOUT_TIMEOUT" >/dev/null 2>"$CLIENT_ERR"
client_rc=$?
set -e

if [[ $server_rc -ne 0 || $client_rc -ne 0 ]]; then
  pods="$(kubectl --kubeconfig "$KUBECONFIG_PATH" -n "$NS" get pods -o wide 2>&1 || true)"
  jq -n \
    --arg namespace "$NS" \
    --arg stack "$STACK_NAME" \
    --arg runtimeClass "${RUNTIME_CLASS_NAME:-default}" \
    --arg serverErr "$(cat "$SERVER_ERR")" \
    --arg clientErr "$(cat "$CLIENT_ERR")" \
    --arg pods "$pods" \
    '{
      status:"fail",
      summary:"Istio-injected workloads did not become Ready",
      details:{
        stack:$stack,
        namespace:$namespace,
        runtimeClass:$runtimeClass,
        serverError:$serverErr,
        clientError:$clientErr,
        pods:$pods
      }
    }'
  exit 0
fi

server_pod="$(kubectl --kubeconfig "$KUBECONFIG_PATH" -n "$NS" get pod -l app="$SERVER" -o jsonpath='{.items[0].metadata.name}')"
client_pod="$(kubectl --kubeconfig "$KUBECONFIG_PATH" -n "$NS" get pod -l app="$CLIENT" -o jsonpath='{.items[0].metadata.name}')"

server_containers="$(kubectl --kubeconfig "$KUBECONFIG_PATH" -n "$NS" get pod -l app="$SERVER" -o jsonpath='{.items[0].spec.containers[*].name}')"
client_containers="$(kubectl --kubeconfig "$KUBECONFIG_PATH" -n "$NS" get pod -l app="$CLIENT" -o jsonpath='{.items[0].spec.containers[*].name}')"
server_init_containers="$(kubectl --kubeconfig "$KUBECONFIG_PATH" -n "$NS" get pod -l app="$SERVER" -o jsonpath='{.items[0].spec.initContainers[*].name}')"
client_init_containers="$(kubectl --kubeconfig "$KUBECONFIG_PATH" -n "$NS" get pod -l app="$CLIENT" -o jsonpath='{.items[0].spec.initContainers[*].name}')"
server_injected="$(kubectl --kubeconfig "$KUBECONFIG_PATH" -n "$NS" get pod -l app="$SERVER" -o jsonpath='{.items[0].metadata.annotations.sidecar\.istio\.io/status}')"
client_injected="$(kubectl --kubeconfig "$KUBECONFIG_PATH" -n "$NS" get pod -l app="$CLIENT" -o jsonpath='{.items[0].metadata.annotations.sidecar\.istio\.io/status}')"
server_runtime_class="$(kubectl --kubeconfig "$KUBECONFIG_PATH" -n "$NS" get pod "$server_pod" -o jsonpath='{.spec.runtimeClassName}')"
client_runtime_class="$(kubectl --kubeconfig "$KUBECONFIG_PATH" -n "$NS" get pod "$client_pod" -o jsonpath='{.spec.runtimeClassName}')"
server_node="$(kubectl --kubeconfig "$KUBECONFIG_PATH" -n "$NS" get pod "$server_pod" -o jsonpath='{.spec.nodeName}')"
client_node="$(kubectl --kubeconfig "$KUBECONFIG_PATH" -n "$NS" get pod "$client_pod" -o jsonpath='{.spec.nodeName}')"
response="$(kubectl --kubeconfig "$KUBECONFIG_PATH" -n "$NS" exec deploy/"$CLIENT" -c curl -- curl -fsS "http://${SVC}.${NS}.svc.cluster.local/" 2>"$CLIENT_CURL_ERR" || true)"

if [[ -n "$server_injected" && -n "$client_injected" && ( "$server_containers $server_init_containers" == *"istio-proxy"* ) && ( "$client_containers $client_init_containers" == *"istio-proxy"* ) && "$response" == "$EXPECTED_RESPONSE" ]]; then
  if [[ -n "$RUNTIME_CLASS_NAME" ]]; then
    summary="Istio sidecar injection worked with RuntimeClass ${RUNTIME_CLASS_NAME}"
  else
    summary="Istio sidecar injection and in-mesh traffic succeeded"
  fi
  jq -n \
    --arg summary "$summary" \
    --arg stack "$STACK_NAME" \
    --arg namespace "$NS" \
    --arg response "$response" \
    --arg server "$server_containers" \
    --arg client "$client_containers" \
    --arg serverInit "$server_init_containers" \
    --arg clientInit "$client_init_containers" \
    --arg serverPod "$server_pod" \
    --arg clientPod "$client_pod" \
    --arg serverNode "$server_node" \
    --arg clientNode "$client_node" \
    --arg serverRuntimeClass "${server_runtime_class:-}" \
    --arg clientRuntimeClass "${client_runtime_class:-}" \
    '{
      status:"pass",
      summary:$summary,
      details:{
        stack:$stack,
        namespace:$namespace,
        response:$response,
        serverContainers:$server,
        clientContainers:$client,
        serverInitContainers:$serverInit,
        clientInitContainers:$clientInit,
        serverPod:$serverPod,
        clientPod:$clientPod,
        serverNode:$serverNode,
        clientNode:$clientNode,
        serverRuntimeClass:$serverRuntimeClass,
        clientRuntimeClass:$clientRuntimeClass
      }
    }'
else
  jq -n \
    --arg stack "$STACK_NAME" \
    --arg namespace "$NS" \
    --arg response "$response" \
    --arg expected "$EXPECTED_RESPONSE" \
    --arg server "$server_containers" \
    --arg client "$client_containers" \
    --arg serverInit "$server_init_containers" \
    --arg clientInit "$client_init_containers" \
    --arg curlErr "$(cat "$CLIENT_CURL_ERR")" \
    --arg serverInjected "$server_injected" \
    --arg clientInjected "$client_injected" \
    --arg serverPod "$server_pod" \
    --arg clientPod "$client_pod" \
    --arg serverNode "$server_node" \
    --arg clientNode "$client_node" \
    --arg serverRuntimeClass "${server_runtime_class:-}" \
    --arg clientRuntimeClass "${client_runtime_class:-}" \
    '{
      status:"fail",
      summary:"Istio sidecar smoke test failed",
      details:{
        stack:$stack,
        namespace:$namespace,
        response:$response,
        expectedResponse:$expected,
        curlError:$curlErr,
        serverContainers:$server,
        clientContainers:$client,
        serverInitContainers:$serverInit,
        clientInitContainers:$clientInit,
        serverInjected:$serverInjected,
        clientInjected:$clientInjected,
        serverPod:$serverPod,
        clientPod:$clientPod,
        serverNode:$serverNode,
        clientNode:$clientNode,
        serverRuntimeClass:$serverRuntimeClass,
        clientRuntimeClass:$clientRuntimeClass
      }
    }'
fi
