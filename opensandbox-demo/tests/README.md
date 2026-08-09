# Tenant Server tests

`tenant-server-smoke.sh` is a repeatable, non-destructive contract test. It creates a
unique temporary tenant, verifies health and tenant-labelled metrics, checks all three
node-local replicas when run with `CHECK_K8S=1`, confirms unauthenticated traffic is
rejected and `/v1/snapshots` is not exposed, then disables the temporary tenant. A
cleanup trap removes the temporary tenant even when an assertion fails. It does not
create a sandbox or alter the warm pool.

Run from a cluster node:

```bash
CHECK_K8S=1 CHECK_PROMETHEUS=1 \
TENANT_SERVER_URL=http://127.0.0.1:18080 ./tenant-server-smoke.sh
```

Run from another machine through a NodePort:

```bash
TENANT_SERVER_URL=http://10.10.0.154:30081 \
TENANT_SERVER_ADMIN_TOKEN='read-from-your-secret-manager' \
./tenant-server-smoke.sh
```

The deployment gate should run this smoke test after every image, manifest, database,
egress-policy, or authentication change. A later integration suite should add a
dedicated disposable sandbox namespace and cover create, command streaming, upload,
download, ownership isolation, pool claim/release, TTL expiry, and egress reset.

The Go unit tests run without Kubernetes, PostgreSQL, or OpenSandbox:

```bash
cd ../tenant-server-go
go test -race -count=1 ./...
```
