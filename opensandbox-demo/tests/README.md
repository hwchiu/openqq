# Tenant Server tests

## Fast company-environment verification

Run the combined gate after applying images, manifests, secrets, KFA, or
PostgreSQL in a new cluster. It checks the Tenant Server, Demo Server, KFA,
Kubernetes rollout state, authentication boundaries, tenant-labelled metrics,
and optionally Prometheus discovery. It creates only a temporary tenant
mapping and removes it through an exit cleanup trap; it does not create a
sandbox or modify the warm pool.

From a control-plane node with `kubectl` configured:

```bash
cd opensandbox-demo/tests
TENANT_SERVER_URL=http://127.0.0.1:30081 \
DEMO_SERVER_URL=http://127.0.0.1:30080 \
CHECK_PROMETHEUS=1 \
./deployment-smoke.sh
```

From an operator laptop through a private NodePort:

```bash
TENANT_SERVER_URL=http://10.10.0.154:30081 \
DEMO_SERVER_URL=http://10.10.0.154:30080 \
TENANT_SERVICEACCOUNT_ADMIN_TOKEN="$ADMIN_TOKEN" \
TENANT_SERVICEACCOUNT_TOKEN="$CLIENT_TOKEN" \
CHECK_K8S=0 CHECK_KFA=0 \
./opensandbox-demo/tests/deployment-smoke.sh
```

If KFA or Prometheus is reachable only from inside the cluster, run the first
form on a cluster node or use `kubectl port-forward` first. A successful gate
ends with `PASS: complete deployment smoke test`. Any non-zero exit code is a
deployment failure and should block traffic release.

`tenant-server-smoke.sh` is a repeatable, non-destructive contract test. It uses the
`kfa-test/kfa-test-client` ServiceAccount token, creates a temporary identity mapping,
verifies health and tenant-labelled metrics, checks all three node-local replicas when
run with `CHECK_K8S=1`, confirms unauthenticated traffic is rejected and
`/v1/snapshots` is not exposed, then disables the temporary tenant. A cleanup trap
removes the temporary tenant even when an assertion fails. It does not create a
sandbox or alter the warm pool.

Run from a cluster node:

```bash
CHECK_K8S=1 CHECK_PROMETHEUS=1 \
TENANT_SERVER_URL=http://127.0.0.1:18080 ./tenant-server-smoke.sh
```

Run from another machine through a NodePort:

```bash
TENANT_SERVER_URL=http://10.10.0.154:30081 \
TENANT_SERVICEACCOUNT_ADMIN_TOKEN='projected-serviceaccount-token' \
./tenant-server-smoke.sh
```

The deployment gate should run this smoke test after every image, manifest, database,
egress-policy, or authentication change. A later integration suite should add a
dedicated disposable sandbox namespace and cover create, command streaming, upload,
download, ownership isolation, pool claim/release, TTL expiry, and egress reset.

That sandbox-level suite is now available as
`tenant-server-integration.sh`. Unlike the deployment smoke test, it creates
one disposable pooled sandbox and verifies command execution, upload,
download, and cleanup. Set `CHECK_EGRESS=1` to also exercise the Tenant Server
egress boundary. Its create wait defaults to 180 seconds because a pool claim
may wait for the OpenSandbox server to report a ready sandbox; override
`SANDBOX_CREATE_TIMEOUT` when the target runtime has a different SLA. Its exit
trap deletes the sandbox and temporary tenant. The request always includes an
explicit `image` together with `extensions.poolRef`; this is required by the
currently deployed OpenSandbox v0.2.2 behavior even though newer schemas mark
the image optional for pooled requests. After the asynchronous create response,
the test retries the first command until the sandbox endpoint is ready; a 404
during that readiness window is expected and is not treated as a permanent
failure.

The Go unit tests run without Kubernetes, PostgreSQL, or OpenSandbox:

```bash
cd ../tenant-server-go
go test -race -count=1 ./...
```

The Demo Server unit tests cover FQDN validation, safe workspace filenames,
and one-event SSE queue behavior:

```bash
python3 -m unittest discover -s ../backend -p 'test_*.py'
```

The PostgreSQL integration tests are skipped unless `TEST_DATABASE_URL` is set.
They verify versioned migrations, KFA UID principal binding, idempotent
migration startup, concurrent quota reservations, ownership conflict
protection, and TTL ownership reconciliation:

```bash
TEST_DATABASE_URL=postgres://postgres:password@127.0.0.1:5432/tenant_test \
go test -race -count=1 -run 'TestPostgres(PrincipalAndQuota|OwnershipReconcile)Integration' ./...
```

The reservation transaction locks the tenant row, counts allocated ownership
plus active reservations, and removes reservations older than ten minutes.
OpenSandbox create is called only after a reservation is committed; success
commits ownership and all other paths release the reservation.

The KFA production overlay can be validated without changing a cluster:

```bash
./kfa-overlay-render-smoke.sh
```

It requires three replicas, a ClusterIP Service, normal Pod networking, and a
PodDisruptionBudget, and rejects an accidental production NodePort or
`hostNetwork` setting.

The CloudNativePG backup overlay can be rendered without applying it:

```bash
./postgres-backup-render-smoke.sh
```

It intentionally contains bucket/endpoint placeholders and no credentials.
Replace them and create the referenced Secret only inside the target cluster.

The HTTPS entrypoint can also be validated without changing a cluster:

```bash
./tenant-server-ingress-render-smoke.sh
```

Before applying the ingress, provision the `opensandbox-tenant-server-tls`
Secret through cert-manager or an external secret manager and replace the
example hostname. The ingress is the only public entrypoint; the OpenSandbox
Service remains internal.
