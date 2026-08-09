# Tenant Server disaster recovery runbook

This runbook covers PostgreSQL state, Tenant Server replicas, KFA identity
bindings, and OpenSandbox ownership. It deliberately separates database
recovery from stateless application rollout.

## Recovery objectives

The production owner must set these values before go-live:

```text
RPO: maximum accepted loss of tenant/audit/ownership state
RTO: maximum time to restore Tenant Server admission
```

The minimum recommended starting target is RPO 15 minutes and RTO 30 minutes,
but the actual target depends on the CloudNativePG backup destination and
whether OpenSandbox sandboxes are disposable.

## What is authoritative

| Data | System of record | Recovery behavior |
| --- | --- | --- |
| Tenant policy | PostgreSQL | Must be restored before traffic opens |
| Principal UID bindings | PostgreSQL `tenant_principals` | Must be restored; rebind only by operator |
| Sandbox ownership | PostgreSQL `sandbox_owners` | Reconcile against OpenSandbox before allowing delete/read |
| Audit events | PostgreSQL `audit_events` | Restore for compliance and incident review |
| OpenSandbox server key | Kubernetes Secret / external secret manager | Rotate if compromise is suspected |
| KFA client authorization | Kubernetes manifest/config | Reapply and verify before requests |
| Running sandbox contents | OpenSandbox runtime | Treat as disposable; do not assume recoverable |

Prometheus and Grafana data are operational evidence, not authorization state.
Restore them independently from their PVC or remote metric storage.

## Normal backup requirements

CloudNativePG must be configured with a durable object-store destination before
the HA Cluster is considered production-ready. The destination must support:

- encrypted base backups;
- WAL archiving / point-in-time recovery;
- retention longer than the tenant audit retention policy;
- credentials delivered by Secret or external secret operator;
- a restore test from a different namespace or cluster.

Do not treat a PostgreSQL PVC snapshot as the only backup. A PVC failure,
operator mistake, or cluster-wide loss can remove both the primary and local
replicas.

The operator should record evidence for every backup cycle:

```bash
kubectl -n opensandbox-tenant-server get cluster opensandbox-postgres-ha
kubectl -n opensandbox-tenant-server get backup
kubectl -n opensandbox-tenant-server describe cluster opensandbox-postgres-ha
```

The backup is not accepted until the CloudNativePG status reports a completed
backup and the object-store retention policy is verified.

## Restore procedure

1. Stop external traffic to Tenant Server. Do not delete the old database yet.
2. Preserve diagnostics: Tenant Server logs, KFA logs, Kubernetes events,
   PostgreSQL status, and the last Prometheus snapshots.
3. Identify the recovery timestamp or backup ID and record the chosen RPO.
4. Restore PostgreSQL into a new temporary namespace/Cluster using the
   CloudNativePG recovery configuration for the selected backup.
5. Wait until all required instances are Ready and verify the restored schema:

   ```sql
   SELECT version, name, applied_at
   FROM schema_migrations
   ORDER BY version;
   SELECT count(*) FROM tenants WHERE enabled;
   SELECT count(*) FROM tenant_principals WHERE enabled;
   SELECT count(*) FROM audit_events;
   ```

6. Run the PostgreSQL integration test against the restored endpoint:

   ```bash
   TEST_DATABASE_URL='postgres://...' \
     go test -race -count=1 -run TestPostgresPrincipalAndQuotaIntegration ./...
   ```

7. Point a disposable Tenant Server deployment at the restored database.
8. Run `deployment-smoke.sh` with KFA and Prometheus checks.
9. Run `tenant-server-integration.sh` against a disposable test tenant. Do
   not run it against a restored production tenant.
10. Reconcile `sandbox_owners` with the OpenSandbox server. Any ownership row
    whose sandbox no longer exists must be marked released by an operator
    procedure; never blindly recreate a sandbox from an ownership row.
11. Switch the private Service/Ingress to the restored Tenant Server only
    after identity, ownership, quota, and metrics checks pass.
12. Keep the old database isolated until the recovery is accepted and the
    incident record is complete.

## Tenant Server loss without database loss

If only application Pods fail:

```bash
kubectl -n opensandbox-tenant-server rollout status \
  deployment/opensandbox-tenant-server --timeout=180s
kubectl -n opensandbox-tenant-server rollout restart \
  deployment/opensandbox-tenant-server
```

Do not delete PostgreSQL, tenant mappings, or all sandboxes as a generic
recovery action. The rolling deployment and PodDisruptionBudget preserve
admission availability while replicas are replaced.

## ServiceAccount compromise or recreation

If a client ServiceAccount is compromised:

1. Disable the tenant or principal binding.
2. Revoke active egress grants and release owned sandboxes.
3. Delete/recreate the ServiceAccount if required.
4. Verify the new `metadata.uid`.
5. Explicitly bind the new UID to the approved tenant.
6. Review `audit_events` for the old principal and tenant activity.

An identically named recreated ServiceAccount must not be trusted solely from
its username. The UID and cluster identity must match.

## Recovery acceptance criteria

- CloudNativePG reports the intended recovery point and Ready instances.
- `schema_migrations` contains every required version exactly once.
- Existing tenant IDs and enabled state match the incident-approved snapshot.
- Principal UID mappings are present; no unexpected same-name principal is
  implicitly trusted.
- PostgreSQL integration test passes.
- Deployment smoke test passes.
- Sandbox integration test passes with a disposable tenant.
- Prometheus sees all Tenant Server replicas.
- Grafana can query tenant request, quota, active sandbox, and error metrics.
- No recovery step deleted unrelated tenants, sandboxes, or warm-pool Pods.

The recovery exercise should be repeated at least quarterly and after every
change to CloudNativePG, object-store credentials, schema migrations, or
Tenant Server ownership logic.
