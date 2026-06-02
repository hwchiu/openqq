# Security Comparison Plan

## Goal

Compare three deployment models and verify which protections each one actually gives:

1. Plain Kubernetes container
2. `agent-sandbox` Sandbox
3. OpenShell-managed access path

## What "safer" should mean

Do not use vague language like "more secure" without a test target. Break it down into:

1. Network reachability
2. Persistence behavior
3. Identity stability
4. Blast radius from another pod
5. Credential handling
6. Policy enforcement point

## Comparison targets

### A. Plain container

Manifest:

1. [k8s/plain-mariadb.yaml](/Users/hwchiu/hwchiu/openqq/k8s/plain-mariadb.yaml)

Expected characteristics:

1. Easy to run
2. No stable higher-level sandbox abstraction
3. Uses ephemeral `emptyDir`
4. No built-in access restriction unless you add `NetworkPolicy`

### B. Agent Sandbox

Manifest:

1. [k8s/agent-sandbox-mariadb.yaml](/Users/hwchiu/hwchiu/openqq/k8s/agent-sandbox-mariadb.yaml)

Expected characteristics:

1. Stable identity
2. Persistent PVC
3. Controller-managed lifecycle
4. Can be combined with Kubernetes `NetworkPolicy`

### C. OpenShell-mediated access

Relevant assets:

1. [k8s/mariadb-networkpolicy.yaml](/Users/hwchiu/hwchiu/openqq/k8s/mariadb-networkpolicy.yaml)
2. [k8s/network-test-deny.yaml](/Users/hwchiu/hwchiu/openqq/k8s/network-test-deny.yaml)
3. [k8s/network-test-allow.yaml](/Users/hwchiu/hwchiu/openqq/k8s/network-test-allow.yaml)

Expected characteristics:

1. Random pods blocked
2. OpenShell path allowed
3. Better story for "agent can reach DB, others cannot"

## Recommended tests

### 1. Reachability test

Question:

Can an arbitrary pod in `default` connect to MariaDB?

Method:

1. Deploy plain MariaDB
2. From `network-test-deny`, test `nc -zvw5 plain-mariadb 3306`
3. Deploy sandboxed MariaDB with NetworkPolicy
4. From `network-test-deny`, test `nc -zvw5 mariadb-sandbox.default.svc.cluster.local 3306`

Expected comparison:

1. Plain container is usually reachable unless you add policy
2. Sandbox + NetworkPolicy should be blocked

### 2. Allowed path test

Question:

Can only the intended path reach MariaDB?

Method:

1. From `network-test-allow` in namespace `openshell`, test `nc -zvw5 mariadb-sandbox.default.svc.cluster.local 3306`
2. From `network-test-deny`, run the same test

Expected comparison:

1. Allow pod succeeds
2. Deny pod fails

### 3. Persistence test

Question:

Does data survive restart?

Method:

1. Insert test data into `plain-mariadb`
2. Delete pod and observe data loss because it uses `emptyDir`
3. Insert test data into `mariadb-sandbox`
4. Delete pod and verify data survives because it uses PVC-backed `volumeClaimTemplates`

Expected comparison:

1. Plain pod loses data
2. Sandbox keeps data

### 4. Identity test

Question:

Does the workload keep a stable name and service identity?

Method:

1. Record pod/service identity for `mariadb-sandbox`
2. Delete the pod
3. Wait for Sandbox readiness
4. Confirm the service FQDN still resolves and the sandbox object identity remains stable

Expected comparison:

1. Sandbox provides a clearer stable service identity model

### 5. Policy enforcement test

Question:

Is policy enforced at the database workload or at the agent runtime?

Method:

1. Note that MariaDB in `agent-sandbox` is not itself an OpenShell-managed sandbox
2. Use OpenShell only as the allowed client path
3. Document that OpenShell constrains the agent, while Kubernetes `NetworkPolicy` constrains DB reachability

Expected conclusion:

1. OpenShell protects the agent runtime
2. Kubernetes policy protects MariaDB exposure
3. Together they are safer than a plain container

## Best proof set for stakeholders

If you need to demonstrate "sandbox is safer than original container", use these three claims only:

1. Plain container can be reached by arbitrary pods unless additional policy is added
2. Sandbox + NetworkPolicy blocks arbitrary pods and permits only the intended path
3. Sandbox + PVC preserves data across restart while the plain `emptyDir` pod does not

## What not to claim

Do not claim:

1. "`agent-sandbox` alone provides OpenShell-style network and filesystem policy"
2. "MariaDB is directly protected by OpenShell policy" unless MariaDB itself runs in an OpenShell-managed sandbox
3. "Sandbox is safer" without naming which property improved
