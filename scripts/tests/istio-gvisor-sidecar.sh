#!/usr/bin/env bash
set -euo pipefail

KUBECONFIG_PATH="$1"
STACK_NAME="${2:-unknown}"
SUFFIX="$(date +%s)"
NS="istio-gvisor-smoke-${SUFFIX}"
SERVER="echo-${SUFFIX}"
CLIENT="curl-${SUFFIX}"
SVC="echo"

cleanup() {
  kubectl --kubeconfig "$KUBECONFIG_PATH" delete ns "$NS" --ignore-not-found --wait=false >/dev/null 2>&1 || true
}
trap cleanup EXIT

kubectl --kubeconfig "$KUBECONFIG_PATH" get runtimeclass gvisor >/dev/null

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
      runtimeClassName: gvisor
      containers:
        - name: echo
          image: hashicorp/http-echo:1.0.0
          args: ["-text=gvisor-mesh-ok"]
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
      runtimeClassName: gvisor
      containers:
        - name: curl
          image: curlimages/curl:8.8.0
          command: ["/bin/sh", "-c", "sleep 365d"]
YAML

set +e
kubectl --kubeconfig "$KUBECONFIG_PATH" -n "$NS" rollout status deploy/"$SERVER" --timeout=120s >/tmp/istio-gvisor-server.out 2>/tmp/istio-gvisor-server.err
server_rc=$?
kubectl --kubeconfig "$KUBECONFIG_PATH" -n "$NS" rollout status deploy/"$CLIENT" --timeout=120s >/tmp/istio-gvisor-client.out 2>/tmp/istio-gvisor-client.err
client_rc=$?
set -e

if [[ $server_rc -ne 0 || $client_rc -ne 0 ]]; then
  jq -n --arg serverErr "$(cat /tmp/istio-gvisor-server.err)" --arg clientErr "$(cat /tmp/istio-gvisor-client.err)" '{status:"fail",summary:"Injected gVisor workload did not become Ready under Istio",details:{serverError:$serverErr,clientError:$clientErr}}'
  exit 0
fi

server_containers="$(kubectl --kubeconfig "$KUBECONFIG_PATH" -n "$NS" get pod -l app="$SERVER" -o jsonpath='{.items[0].spec.containers[*].name}')"
client_containers="$(kubectl --kubeconfig "$KUBECONFIG_PATH" -n "$NS" get pod -l app="$CLIENT" -o jsonpath='{.items[0].spec.containers[*].name}')"
server_init_containers="$(kubectl --kubeconfig "$KUBECONFIG_PATH" -n "$NS" get pod -l app="$SERVER" -o jsonpath='{.items[0].spec.initContainers[*].name}')"
client_init_containers="$(kubectl --kubeconfig "$KUBECONFIG_PATH" -n "$NS" get pod -l app="$CLIENT" -o jsonpath='{.items[0].spec.initContainers[*].name}')"
server_injected="$(kubectl --kubeconfig "$KUBECONFIG_PATH" -n "$NS" get pod -l app="$SERVER" -o jsonpath='{.items[0].metadata.annotations.sidecar\.istio\.io/status}')"
client_injected="$(kubectl --kubeconfig "$KUBECONFIG_PATH" -n "$NS" get pod -l app="$CLIENT" -o jsonpath='{.items[0].metadata.annotations.sidecar\.istio\.io/status}')"
response="$(kubectl --kubeconfig "$KUBECONFIG_PATH" -n "$NS" exec deploy/"$CLIENT" -c curl -- curl -fsS "http://${SVC}.${NS}.svc.cluster.local/" 2>/tmp/istio-gvisor-curl.err || true)"

if [[ -n "$server_injected" && -n "$client_injected" && ( "$server_containers $server_init_containers" == *"istio-proxy"* ) && ( "$client_containers $client_init_containers" == *"istio-proxy"* ) && "$response" == "gvisor-mesh-ok" ]]; then
  jq -n --arg response "$response" --arg server "$server_containers" --arg client "$client_containers" --arg serverInit "$server_init_containers" --arg clientInit "$client_init_containers" '{status:"pass",summary:"Istio sidecar injection worked with RuntimeClass gvisor",details:{response:$response,serverContainers:$server,clientContainers:$client,serverInitContainers:$serverInit,clientInitContainers:$clientInit}}'
else
  jq -n --arg response "$response" --arg server "$server_containers" --arg client "$client_containers" --arg serverInit "$server_init_containers" --arg clientInit "$client_init_containers" --arg curlErr "$(cat /tmp/istio-gvisor-curl.err)" --arg serverInjected "$server_injected" --arg clientInjected "$client_injected" '{status:"degraded",summary:"Injected gVisor workloads started, but mesh traffic or proxy behavior degraded",details:{response:$response,serverContainers:$server,clientContainers:$client,serverInitContainers:$serverInit,clientInitContainers:$clientInit,curlError:$curlErr,serverInjected:$serverInjected,clientInjected:$clientInjected}}'
fi
