# OpenSandbox deployment and operating guide

This document records the OpenSandbox configuration that is currently running
in the kubeadm cluster. It is intended to be copied to another Kubernetes
environment and adapted only where the storage class, registry, public ingress,
or resource capacity differs.

## Architecture

```text
Browser
  |
  v
opensandbox-demo (FastAPI + static frontend)
  |
  v
opensandbox-server:8080 (ClusterIP, internal only)
  |
  v
BatchSandbox CRD + python-warm-pool
  |
  v
10 pre-warmed Python pods, expandable to 30

Each pooled sandbox pod also contains an OpenSandbox egress sidecar. The
backend changes the sidecar policy through its authenticated HTTP API; the
browser never receives the egress token or Kubernetes API credentials.
```

The browser never receives the OpenSandbox API endpoint or execution token.
The demo backend creates an API sandbox with `extensions.poolRef`, uploads
files, executes commands through Execd, and proxies downloads.

## Current deployment inventory

| Item | Current value |
| --- | --- |
| Demo URL | `http://23.100.89.166:8080` |
| Demo namespace | `opensandbox-system` |
| Sandbox namespace | `opensandbox` |
| Demo Service | `opensandbox-demo`, `NodePort 30080` |
| OpenSandbox API Service | `opensandbox-server`, internal `ClusterIP:8080` |
| Server replicas | `1` |
| Demo replicas | `1` |
| Server state | SQLite on `opensandbox-server-data` |
| Server PVC | `2Gi`, `ReadWriteOnce`, `azure-disk-premium` |
| Sandbox timeout | `180` seconds in the demo backend |

The public demo URL is provided by the cluster's public node address and
NodePort. The OpenSandbox API itself is not public; access goes through the
demo backend or an internal port-forward.

## Versions and images

The validated deployment uses:

| Component | Version/image |
| --- | --- |
| OpenSandbox server | `opensandbox/server:v0.2.2` |
| Kubernetes controller | `sandbox-registry.cn-zhangjiakou.cr.aliyuncs.com/opensandbox/controller:v0.2.0` |
| Execd installer | `opensandbox/execd:v1.0.21` |
| Egress sidecar | `opensandbox/egress:v1.1.5` |
| Sandbox runtime | `python:3.12-slim` |
| API/frontend container | `python:3.12-slim` |

Use an accessible registry mirror if another cluster cannot pull these images.

## Prerequisites

- Kubernetes cluster with a working CNI and enough capacity for the pool.
- OpenSandbox Kubernetes controller installed, including `BatchSandbox` and
  `Pool` CRDs.
- A storage class supporting `ReadWriteOnce` Azure Disk or an equivalent block
  storage class.
- `kubectl` configured for the target cluster.

Install the controller with the matching Helm release before applying
`k8s/platform.yaml`:

```bash
helm upgrade --install opensandbox-controller \
  https://github.com/opensandbox-group/OpenSandbox/releases/download/helm/opensandbox-controller/0.2.0/opensandbox-controller-0.2.0.tgz \
  --namespace opensandbox-system \
  --create-namespace
```

Verify the CRDs:

```bash
kubectl api-resources | grep -E 'batchsandboxes|pools'
kubectl get crd batchsandboxes.sandbox.opensandbox.io pools.sandbox.opensandbox.io
```

## Server configuration

The server is deployed by `k8s/platform.yaml` with:

- internal `ClusterIP` service on port `8080`;
- Kubernetes `BatchSandbox` provider;
- `opensandbox/execd:v1.0.21` as the Execd installer image;
- SQLite state at `/data/opensandbox.db`;
- a 2Gi `ReadWriteOnce` PVC;
- `Recreate` deployment strategy.

The `Recreate` strategy is required because the SQLite PVC is RWO. A normal
rolling update can leave the old pod attached while the new pod is scheduled on
another node, producing an Azure Disk `Multi-Attach` error. The tradeoff is a
short server interruption during a server rollout.

The server currently uses `OPENSANDBOX_INSECURE_SERVER=YES`, but its Service is
internal only. Do not expose this Service directly to the Internet without
adding authentication and TLS.

The server ConfigMap also sets `max_sandbox_timeout_seconds=900`,
`limit_concurrency=128`, `thread_pool_size=32`, Kubernetes
`workload_provider=batchsandbox`, `image_pull_policy=IfNotPresent`, informer
support, direct ingress mode, and SQLite storage at `/data/opensandbox.db`.

## Warm pool configuration

The current pool is `opensandbox/python-warm-pool`:

```yaml
capacitySpec:
  bufferMin: 0
  bufferMax: 0
  poolMin: 10
  poolMax: 30
```

This means:

- start with 10 warm pods;
- clients claim those 10 pods one by one;
- the first claim changes the state to `9 available / 1 allocated` and does not
  create a replacement pod;
- when all 10 are allocated, later requests may create more pods up to 30;
- deleting or expiring a sandbox returns the allocation to the pool.

Each warm pod requests and limits `500m CPU` and `512Mi memory`. Ten warm pods
therefore reserve approximately 5 vCPU and 5Gi memory before any expansion.
Adjust `poolMax` and the pod resources to match the target cluster quota.

The pool template must contain:

- `python:3.12-slim` sandbox container;
- `execd-installer` init container;
- shared `/opt/opensandbox` `emptyDir`;
- `EXECD=/opt/opensandbox/execd`;
- `mkdir -p /workspace` before starting Execd;
- `automountServiceAccountToken: false`.

It also contains the egress sidecar:

- `opensandbox/egress:v1.1.5`;
- `OPENSANDBOX_EGRESS_MODE=dns+nft`;
- HTTP policy API on port `18080`;
- `defaultAction: deny` with an administrator baseline allow rule for the
  internal OpenSandbox server Service DNS name;
- `NET_ADMIN` only inside the sandbox pod's egress sidecar.

The sidecar receives `OPENSANDBOX_EGRESS_TOKEN` from a Secret in the
`opensandbox` namespace. The demo backend receives the same value from a
Secret in `opensandbox-system`. Keep this token out of frontend code and
source control.

## Deploy the server and pool

First create the demo token and apply the platform resources:

```bash
kubectl -n opensandbox-system create secret generic opensandbox-demo-secret \
  --from-literal=token='<long-random-demo-token>' \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl apply --validate=false -f k8s/platform.yaml
```

Create one random token and store it in both namespaces. The value must be the
same in both Secrets:

```bash
EGRESS_TOKEN="$(openssl rand -hex 32)"

kubectl -n opensandbox create secret generic opensandbox-egress-secret \
  --from-literal=token="$EGRESS_TOKEN" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n opensandbox-system create secret generic opensandbox-egress-secret \
  --from-literal=token="$EGRESS_TOKEN" \
  --dry-run=client -o yaml | kubectl apply -f -
```

Create the backend/frontend ConfigMaps and restart the demo deployment:

```bash
kubectl -n opensandbox-system create configmap opensandbox-demo-backend \
  --from-file=app.py=backend/app.py \
  --from-file=requirements.txt=backend/requirements.txt \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n opensandbox-system create configmap opensandbox-demo-frontend \
  --from-file=index.html=frontend/index.html \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n opensandbox-system rollout restart deployment/opensandbox-demo
kubectl -n opensandbox-system rollout status deployment/opensandbox-demo --timeout=180s
```

The demo deployment uses these important environment variables:

```text
OPENSANDBOX_SERVER_URL=http://opensandbox-server.opensandbox-system.svc.cluster.local:8080
OPENSANDBOX_EXEC_BASE_URL_TEMPLATE=http://opensandbox-server.opensandbox-system.svc.cluster.local:8080/v1/sandboxes/{sandbox_id}/proxy/44772
OPENSANDBOX_POOL_REF=python-warm-pool
RUN_TTL_SECONDS=180
OPENSANDBOX_EGRESS_ALLOWED_FQDNS=pypi.org,files.pythonhosted.org,github.com,api.github.com,example.com,google.com,www.google.com
```

The Execd proxy port (`44772`) must match the Execd configuration used by the
installed OpenSandbox server/controller version.

The demo application exposes `/health`, installs its Python dependencies at
container startup, and mounts the backend/frontend source from ConfigMaps
`opensandbox-demo-backend` and `opensandbox-demo-frontend`.

## Client/session behavior

The first browser execution calls:

```text
POST /api/runs
```

The backend creates one OpenSandbox session using the warm pool. Later code
executions in the same browser session call:

```text
POST /api/runs/{run_id}/execute
```

and reuse the same sandbox ID and `/workspace`.

Interactive commands use:

```text
POST /api/runs/{run_id}/commands
```

Files use:

```text
GET    /api/runs/{run_id}/files
GET    /api/runs/{run_id}/files/download?path=/workspace/result.txt
DELETE /api/runs/{run_id}
```

Dynamic FQDN egress is managed by the backend, not by granting the caller
Kubernetes permissions:

```text
GET    /api/runs/{run_id}/egress
PATCH  /api/runs/{run_id}/egress   body: {"action":"allow","target":"example.com"}
DELETE /api/runs/{run_id}/egress   body: {"target":"example.com"}
```

Only administrator-approved FQDNs in `OPENSANDBOX_EGRESS_ALLOWED_FQDNS` are
accepted. URLs, IP addresses, CIDRs, and arbitrary domains are rejected. The
baseline OpenSandbox server FQDN cannot be removed by a client.

The frontend also supports Python execution, repeated commands in the same
sandbox, file upload into `/workspace`, file listing, file download, streamed
stdout/stderr, and explicit session deletion.

The backend clears `/workspace` when a sandbox is first claimed and when it is
released. It does not clear `/workspace` between executions in the same
session, so an agent can preserve state across commands and reruns.

Closing the browser does not reliably send DELETE. The sandbox therefore relies
on `RUN_TTL_SECONDS=180`; in practice the pool becomes available again shortly
after the three-minute expiration. Explicitly deleting the session returns it
faster.

## Direct API verification

From a pod inside the cluster, use the Service DNS name. From a control-plane
host, use the Service ClusterIP or port-forward:

```bash
kubectl -n opensandbox-system port-forward svc/opensandbox-server 18080:8080
curl http://127.0.0.1:18080/health
curl 'http://127.0.0.1:18080/v1/sandboxes?page=1&pageSize=200' | jq
```

Create a pooled sandbox directly:

```bash
curl -X POST http://127.0.0.1:18080/v1/sandboxes \
  -H 'Content-Type: application/json' \
  -d '{
    "timeout": 180,
    "extensions": {"poolRef": "python-warm-pool"},
    "metadata": {"source": "manual-test"}
  }'
```

Inspect pool allocation:

```bash
kubectl -n opensandbox get pool python-warm-pool \
  -o jsonpath='total={.status.total} available={.status.available} allocated={.status.allocated}{"\n"}'
kubectl -n opensandbox get batchsandbox
kubectl -n opensandbox get pods -l purpose=opensandbox-warm-pool -o wide
```

Delete the test sandbox when finished:

```bash
curl -X DELETE http://127.0.0.1:18080/v1/sandboxes/<sandbox-id>
```

## Egress policy and experiment results

The current policy model is:

```text
defaultAction: deny
allow: opensandbox-server.opensandbox-system.svc.cluster.local
```

The sidecar reports `mode=enforcing` and `enforcementMode=dns+nft` when it is
ready. The frontend's **Sandbox egress FQDN** panel can allow or remove an
approved FQDN for the current sandbox. The tested sequence was:

1. Allow `example.com` through the frontend/API.
2. Run Python inside the sandbox and connect to `https://example.com` — HTTP
   status `200` was returned.
3. Remove `example.com`.
4. Repeat the request — DNS resolution failed, confirming enforcement.
5. Request `not-allowlisted.example` — the backend rejected it with HTTP 400.
6. Allow `www.google.com`, then run
   `urllib.request.urlopen("https://www.google.com")` — HTTP status `200` was
   returned.

The backend resets the policy to the baseline when a pooled sandbox is first
claimed and again on explicit session deletion. This is important because a
pooled pod survives one client's sandbox lifecycle and is reused by another
client. When a browser simply disappears, the three-minute TTL releases the
allocation; the next claim performs the safety reset. Therefore, a dynamic
rule is not guaranteed to disappear immediately at TTL expiry in the current
demo. If immediate cleanup independent of the backend is required, add an
in-cluster controller that watches sandbox expiry/release and calls the
sidecar reset API.

The OpenSandbox egress documentation also warns that a Pool-created pod must
include its egress sidecar in the Pool template; a per-request lifecycle
network policy cannot retrofit a sidecar onto an already-created pooled pod.
This deployment follows that model and uses the runtime `/policy` API for
per-client FQDN changes.

Swagger is available at `/docs` on the internal server. The server currently
does not expose a Prometheus `/metrics` endpoint; Kubernetes pod/node metrics
must be collected through the existing monitoring stack.

## Validation checklist

```bash
kubectl -n opensandbox-system get pods -o wide
kubectl -n opensandbox get pool python-warm-pool
kubectl -n opensandbox get pods -l purpose=opensandbox-warm-pool
kubectl -n opensandbox-system get pvc opensandbox-server-data
kubectl -n opensandbox-system rollout status deployment/opensandbox-server
kubectl -n opensandbox-system rollout status deployment/opensandbox-demo
```

Expected steady state:

```text
opensandbox-server:       1/1 Running
opensandbox-demo:         1/1 Running
python-warm-pool:         total=10 available=10 allocated=0
opensandbox-server-data:  Bound, 2Gi, RWO
```

## Security and production gaps

This demo executes arbitrary Python supplied by a user. Before using it as a
production service, add real user authentication, per-user authorization and
quotas, durable session storage, rate limiting, output limits, audit logging,
TLS, network egress policy, and a hardened runtime such as gVisor, Kata, or
Firecracker. Keep the OpenSandbox server Service private and expose only an
authenticated application/API gateway.

## Tenant gateway modes

完整的 tenant gateway、DB schema、warm-pool claim、egress state machine 與
tenant metrics 架構請參考
[TENANT-GATEWAY-ARCHITECTURE.md](TENANT-GATEWAY-ARCHITECTURE.md)。

The tenant gateway is designed as the tenant-aware boundary in front of the
single OpenSandbox Server API key. A tenant never submits or receives the
OpenSandbox server key. The gateway validates a tenant key, checks scopes and
quota, adds the server-side `OPEN-SANDBOX-API-KEY`, and forwards only the
allowed OpenSandbox API surface.

Supported tenant stores:

```text
TENANT_STORE=sqlite    durable dynamic store on the gateway PVC
TENANT_STORE=vault     Vault KV v2, short-cache reads, no gateway restart
TENANT_STORE=configmap read-only development snapshot, reloads on file change
```

The gateway must preserve tenant ownership for every sandbox ID. It exposes
create, lifecycle, command and file-proxy operations, but intentionally returns
404 for snapshot and unknown routes. Upload requests are bounded by
`MAX_BODY_BYTES`; downloads and SSE command responses are streamed rather than
buffered as a complete response. Prometheus metrics include:

```text
opensandbox_gateway_requests_total{tenant,method,route,status}
opensandbox_gateway_request_duration_seconds{tenant,method,route}
opensandbox_gateway_sandboxes_created_total{tenant}
opensandbox_gateway_sandboxes_deleted_total{tenant}
opensandbox_gateway_active_sandboxes{tenant}
opensandbox_gateway_commands_total{tenant}
opensandbox_gateway_uploaded_bytes_total{tenant}
opensandbox_gateway_downloaded_bytes_total{tenant}
opensandbox_gateway_quota_rejections_total{tenant}
```

For Vault mode, the gateway authenticates with the Kubernetes auth method and
uses a KV v2 tenant index plus one record per tenant. The cache is deliberately
short so enable/disable/key rotation takes effect without a Deployment
restart. Vault should be external or highly available before using this mode
for production.

The current cluster deployment uses SQLite mode and keeps its state on the
gateway PVC. The gateway is exposed internally through the private ClusterIP
and externally through NodePort `30081`; the OpenSandbox Server itself remains
ClusterIP-only. Create a tenant without restarting the gateway:

```bash
ADMIN_TOKEN="$(kubectl -n opensandbox-gateway get secret opensandbox-tenant-gateway-secrets \
  -o jsonpath='{.data.admin-token}' | base64 -d)"

curl -X POST http://<gateway-private-ip>:8080/admin/tenants \
  -H "X-Gateway-Admin-Token: $ADMIN_TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"tenant_id":"team-a","max_concurrent_sandboxes":3}'
```

The response contains the tenant key once. Store it in the caller's secret
manager and send it as `Authorization: Bearer <tenant-key>` to the normal
OpenSandbox `/v1/...` endpoints. The gateway records the sandbox-to-tenant
ownership mapping, so one tenant cannot list or operate another tenant's
sandbox.

Useful Prometheus queries for tenant usage are:

```promql
sum by (tenant) (rate(opensandbox_gateway_requests_total[5m]))
sum by (tenant) (rate(opensandbox_gateway_sandboxes_created_total[15m]))
sum by (tenant) (opensandbox_gateway_active_sandboxes)
sum by (tenant) (rate(opensandbox_gateway_commands_total[5m]))
sum by (tenant) (rate(opensandbox_gateway_uploaded_bytes_total[5m]))
sum by (tenant) (rate(opensandbox_gateway_downloaded_bytes_total[5m]))
```

These labels are intentionally attached at the gateway boundary, where tenant
identity is known. Do not add tenant labels to sandbox Pod names or arbitrary
request paths; that would create high-cardinality metrics. The bundled
ServiceMonitor scrapes `/metrics`, and its target is verified through the
Prometheus `up{job="opensandbox-tenant-gateway"}` query.

### Current deployment verification

The deployed gateway runs in `opensandbox-gateway` with SQLite mode enabled
and state stored on the `opensandbox-tenant-gateway-data` PVC. Its private
ClusterIP is `10.96.10.36:8080` and its NodePort is `30081`; OpenSandbox Server
remains ClusterIP-only.

Verified after deployment:

- tenant sandbox create/list and ownership isolation;
- `/v1/snapshots` rejected with HTTP 404;
- adding a tenant without gateway restart;
- Prometheus target `up{job="opensandbox-tenant-gateway"} = 1`;
- tenant-labelled request, sandbox and active-session metrics;
- test sandbox deletion and workload cleanup.

Validation tenants were `demo` and `analytics`. Tenant keys are returned only
once by `POST /admin/tenants`; the gateway stores only a hash, so a lost key
must be replaced rather than retrieved.
