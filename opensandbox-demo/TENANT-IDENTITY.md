# Tenant identity design

This document defines how Tenant Server decides which tenant owns an
authenticated request. The important distinction is:

```text
token       = short-lived proof presented by the client
principal   = Kubernetes ServiceAccount identity returned by KFA
tenant      = stable business/account boundary stored by Tenant Server
session     = sandbox ownership record assigned to a tenant
```

## Decision summary

Tenant Server never stores or compares the client bearer token as a tenant
identifier. KFA validates the token and returns a Kubernetes `UserInfo`.
Tenant Server uses the cluster identity and the ServiceAccount object UID as
the strong principal binding:

```text
authoritative principal key = <cluster-id>/<service-account-uid>
```

The username remains useful and is stored as metadata:

```text
system:serviceaccount:<namespace>:<service-account-name>
```

The username is parsed into namespace and ServiceAccount name, but it is not
the strongest identity because the same name can be reused after deletion.

## Key roles

| Key | Example | Purpose | Can change during token renewal? |
| --- | --- | --- | --- |
| `tenant_id` | `team-a` | Stable business identity and metrics label | No |
| `cluster_id` | `local-cluster` | Separates identities from different clusters | No |
| `username` | `system:serviceaccount:team-a:runner` | Human-readable identity and compatibility lookup | No |
| `namespace` | `team-a` | Parsed metadata and operational filtering | No |
| `service_account_name` | `runner` | Parsed metadata and audit display | No |
| `service_account_uid` | `8c7e...` | Strong Kubernetes object identity | No |
| bearer token | JWT/string | Authentication proof only | Yes |
| token `jti` | `6048...` | Individual credential identifier | Yes |

The token, token hash, JWT `jti`, `iat`, and `exp` must not be used as the
tenant key. They are expected to change as projected ServiceAccount tokens are
renewed.

## Request workflow

```text
Client
  │ Authorization: Bearer <short-lived ServiceAccount token>
  ▼
Tenant Server
  │ TokenReview: client token
  │ Authorization: Tenant Server's projected ServiceAccount token
  ▼
KFA
  │ authenticated, username, uid, cluster-name
  ▼
Tenant Server
  │ principal lookup: cluster-id + service-account-uid
  │ authorization: enabled tenant, scopes, quota
  ▼
PostgreSQL
  │ tenant_id
  ▼
OpenSandbox using server-side OpenSandbox API key
```

The client never receives the OpenSandbox API key and does not need direct
KFA or Kubernetes API permissions. Tenant Server's own ServiceAccount token is
only the caller credential used when asking KFA to review the client token.

## PostgreSQL binding

The current schema keeps the binding on the tenant record:

```text
tenants
  tenant_id
  cluster_name
  namespace
  service_account
  principal_uid
  scopes
  max_concurrent
  enabled
```

The authoritative lookup requires the KFA UID to match. A unique partial index
prevents one ServiceAccount UID in a cluster from being bound to two tenants.
The existing username identity index remains for compatibility and human
operations.

An eventual multi-principal schema can move the identity columns into a
`tenant_principals` table:

```text
tenant_principals
  tenant_id
  cluster_id
  principal_uid
  namespace
  service_account_name
  enabled
```

That would allow several ServiceAccounts to represent one tenant without
changing sandbox ownership or metrics. The current implementation supports
the strong UID column and preserves the existing one-principal admin API.

## ServiceAccount lifecycle and risks

### Token renewal

The projected token expires and is replaced. KFA still returns the same
username and ServiceAccount UID, so the same tenant mapping is used. No DB
update, rollout, or metrics reset is required.

### Pod restart or redeploy

A Pod restart does not change the ServiceAccount object. The new Pod receives a
new projected token but authenticates to the same principal. Tenant Server
replicas therefore remain interchangeable.

### ServiceAccount deleted and recreated with the same name

This is the important security boundary:

```text
old: namespace=team-a, name=runner, uid=UID-A
new: namespace=team-a, name=runner, uid=UID-B
```

The username is identical, but the UID is different. The new ServiceAccount
must not automatically inherit the old tenant. An administrator must create a
new explicit binding or update the existing tenant after reviewing the change.

Without UID binding, a compromised or accidentally recreated same-name
ServiceAccount could regain the old tenant's scopes and sandbox ownership.

### Namespace recreation

Recreating a namespace also creates new ServiceAccount objects. The UID check
prevents a same-name account in the new namespace lifecycle from silently
reusing an old binding. Namespace and name are still checked as defense in
depth and for operator visibility.

### Cluster replacement or restore

`cluster_name` comes from KFA's trusted cluster metadata, not from the client.
Each cluster must have a unique configured cluster identity. When a cluster is
replaced, operators should review its principal bindings even if names look
the same. The UID and cluster identity must both match before authorization.

## Migration behavior

Older rows may contain username fields but an empty `principal_uid`. The
database migration adds the nullable-in-practice empty-string column and keeps
the old username lookup temporarily. On the first successful KFA request, the
observed `user.uid` is written to that row. Future requests require the UID.

This gives an operational migration path:

1. Deploy the new Tenant Server image.
2. Existing mapped ServiceAccounts authenticate once.
3. Tenant Server backfills their UID in PostgreSQL.
4. Review `/admin/tenants` output for non-empty `principal_uid`.
5. Reject or explicitly rebind any remaining legacy rows.

New admin mappings can include `principal_uid` immediately and do not need the
fallback path.

## Admin identity configuration

`TENANT_SERVER_ADMIN_IDENTITIES` accepts either form:

```text
# readable compatibility form
local-cluster/opensandbox-tenant-server/opensandbox-tenant-server

# strong form
local-cluster/<service-account-uid>
```

The strong form is preferred for production. The readable form remains useful
during migration and for the fixed platform administrator ServiceAccount.

Obtain a ServiceAccount UID with:

```bash
kubectl -n team-a get serviceaccount runner \
  -o jsonpath='{.metadata.uid}{"\n"}'
```

## Operations and metrics compatibility

The tenant label remains the logical `tenant_id`, not the token, UID, or full
username. This keeps dashboards stable across token rotation, Pod restarts,
and principal reauthentication:

```text
opensandbox_tenant_server_requests_total{tenant="team-a",...}
```

Do not add raw token, JWT `jti`, or sandbox ID as a Prometheus label. They
would create high cardinality and make long-term metrics expensive. The UID
may be recorded in structured audit logs or PostgreSQL, but should not be a
normal dashboard label.

Recommended operational checks:

```bash
curl -H "Authorization: Bearer $ADMIN_TOKEN" \
  "$TENANT_SERVER/admin/tenants" | jq '.[] | {tenant_id,cluster_name,namespace,service_account,principal_uid,enabled}'

kubectl -n team-a get serviceaccount runner \
  -o jsonpath='{.metadata.uid}{"\n"}'
```

When a ServiceAccount is intentionally recreated:

1. Disable the old tenant mapping or revoke its grants.
2. Verify the new UID and ownership request.
3. Create or update the explicit principal binding.
4. Run the deployment smoke test.
5. Confirm tenant metrics continue under the same logical `tenant_id` only if
   the rebind was approved.

The existing smoke tests remain valid because they use a temporary
username-based mapping and the first authenticated request upgrades it with
the KFA UID. The test cleanup removes the temporary tenant afterward.
