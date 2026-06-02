# MariaDB Sandbox Security Verification

## Important distinction

The current MariaDB example is an `agent-sandbox` `Sandbox` object.

That proves:

1. MariaDB can run as a single persistent sandboxed workload
2. It gets a stable identity and persistent volume
3. The controller manages its lifecycle

It does **not** automatically prove:

1. OpenShell filesystem policy is protecting MariaDB
2. OpenShell network policy is protecting MariaDB
3. Arbitrary in-cluster pods are blocked from reaching MariaDB

OpenShell policy enforcement primarily applies to OpenShell-managed sandboxes, not every arbitrary Kubernetes workload.

## What we can verify today

### 1. Functional sandbox verification

This is already proven if all of the following succeed:

```bash
kubectl --kubeconfig generated/kubeconfig get sandbox mariadb-sandbox
kubectl --kubeconfig generated/kubeconfig get pod mariadb-sandbox
kubectl --kubeconfig generated/kubeconfig get pvc | grep mariadb
kubectl --kubeconfig generated/kubeconfig exec mariadb-sandbox -- mariadb -uroot -pchange-me-root-password -e 'SELECT VERSION();'
```

### 2. Network isolation verification

Apply the NetworkPolicy that only allows ingress from the OpenShell gateway pod:

```bash
kubectl --kubeconfig generated/kubeconfig apply -f k8s/mariadb-networkpolicy.yaml
```

Create a generic test pod in `default`:

```bash
kubectl --kubeconfig generated/kubeconfig apply -f k8s/network-test-deny.yaml
```

Then verify a random pod in `default` cannot reach MariaDB:

```bash
kubectl --kubeconfig generated/kubeconfig exec network-test-deny -- /bin/sh -c 'nc -zvw5 mariadb-sandbox.default.svc.cluster.local 3306'
```

Expected result:

The connection should fail or time out.

Then verify the OpenShell pod can still reach MariaDB:

```bash
kubectl --kubeconfig generated/kubeconfig exec -n openshell openshell-0 -- /bin/sh -c 'nc -zvw5 mariadb-sandbox.default.svc.cluster.local 3306'
```

Expected result:

The connection should succeed.

### 3. Persistence verification

Write test data:

```bash
kubectl --kubeconfig generated/kubeconfig exec mariadb-sandbox -- mariadb -uroot -pchange-me-root-password -e "CREATE DATABASE IF NOT EXISTS verifydb; USE verifydb; CREATE TABLE IF NOT EXISTS t (id INT PRIMARY KEY); INSERT IGNORE INTO t VALUES (1); SELECT * FROM t;"
```

Delete only the pod:

```bash
kubectl --kubeconfig generated/kubeconfig delete pod mariadb-sandbox
```

Wait for the sandbox-managed pod to return, then query again:

```bash
kubectl --kubeconfig generated/kubeconfig wait --for=condition=Ready sandbox/mariadb-sandbox --timeout=180s
kubectl --kubeconfig generated/kubeconfig exec mariadb-sandbox -- mariadb -uroot -pchange-me-root-password -e "SELECT * FROM verifydb.t;"
```

Expected result:

The row should still exist, proving the PVC-backed data survived restart.

## What we cannot honestly claim yet

We cannot honestly say MariaDB is "secured by OpenShell policy" unless MariaDB itself is running inside an OpenShell-managed sandbox or is fronted by a path where OpenShell policy is the enforcement point.

Right now the stronger claim is:

1. MariaDB is running inside an `agent-sandbox` managed singleton pod
2. We can restrict who reaches it with Kubernetes `NetworkPolicy`
3. We can verify persistence and stable identity

## Recommended secure architecture

For a realistic setup:

1. Run MariaDB as a Kubernetes workload or sandbox with strict `NetworkPolicy`
2. Run the AI agent inside OpenShell
3. Allow only the OpenShell gateway or sandbox namespace to reach MariaDB
4. Keep DB credentials in Kubernetes `Secret`, not inline env vars

That gives you a meaningful security story:

1. OpenShell constrains the agent runtime
2. Kubernetes policy constrains access to MariaDB
3. MariaDB is not broadly exposed to the cluster
