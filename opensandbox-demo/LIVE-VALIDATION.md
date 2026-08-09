# Live validation record

This file records evidence from the three-node private lab cluster. It is
kept separate from the production manifests because the lab currently has a
known CNI Service/DNS routing limitation.

## Environment

Validated from `cp-0` (`hw-k8s-3`) on 2026-08-09:

- `hw-k8s-1`, `hw-k8s-2`, and `hw-k8s-3` are `Ready` on Kubernetes v1.30.14.
- Tenant Server has three Ready replicas using
  `hwchiu/mon:tenant-server-latest` and PostgreSQL.
- KFA is running as one lab replica behind private NodePort `30082`.
- Prometheus and Grafana are running; Prometheus can scrape all three current
  host-network Tenant Server endpoints.
- OpenSandbox warm-pool pods are still running; the validation scripts did not
  remove the pool.

## Passed gates

```text
Tenant Server smoke test: PASS
  - health and PostgreSQL store
  - three replicas and per-replica health
  - KFA ServiceAccount authentication
  - unauthenticated request rejection
  - snapshot route rejection
  - tenant-labelled metrics
  - Prometheus reports 3 healthy targets
```

The smoke test creates a disposable tenant and ServiceAccount and removes both
through an exit cleanup trap.

## Sandbox integration diagnosis and current gate

The disposable sandbox integration test did not pass:

```text
Tenant Server sandbox create: HTTP 502 upstream unavailable
```

The same create request sent directly from `cp-0` to the OpenSandbox ClusterIP
also timed out after 45 seconds with no HTTP status. OpenSandbox server logs
showed health/list requests but no corresponding `POST /v1/sandboxes`; no
sandbox pod was created before the client timeout. A later controller log
showed that the request eventually created one BatchSandbox and reached
`Succeed`, after which its TTL deleted the BatchSandbox and returned the pool
to ten available pods. The API list nevertheless retained one stale
`direct-diag` record, while its DELETE API returned `SANDBOX_NOT_FOUND`.
This proves the failure is in the underlying
OpenSandbox create path or its controller/API interaction, not a tenant quota
rejection or KFA authentication failure. The temporary tenant and ServiceAccount
were cleaned up.

Do not mark sandbox lifecycle, command, file transfer, or egress live
integration as accepted until `tests/tenant-server-integration.sh` passes with
`CHECK_EGRESS=1`.
The stale diagnostic record was cleared by a controlled OpenSandbox server
restart after confirming that no BatchSandbox remained. No PVC or warm-pool
resource was deleted.

A subsequent direct request with an explicit image returned HTTP 202 and a
`Running` sandbox. The original 502 was reproduced as a lab routing failure:
the Tenant Server NodePort distributed requests across all three
host-networked replicas, while only `10.10.0.154` could reach the
OpenSandbox ClusterIP. As a lab-only diagnostic, OpenSandbox was temporarily
exposed through private NodePort `30083` and Tenant Server was pointed at
`http://10.10.0.154:30083`; all three nodes could then reach the OpenSandbox
health endpoint and the create request passed.

The next integration attempt reached sandbox creation and claimed a warm-pool
pod, but command execution timed out. Direct testing from the OpenSandbox
server Pod showed that `10.244.0.172` can reach same-node sandbox Pods but
cannot reach sandbox Pods on `10.244.3.0/24` or `10.244.4.0/24`. Cilium's
VXLAN packets leave `10.10.0.154` but are not received on the other nodes'
private interfaces. The Kubernetes Node and CiliumNode addresses are now all
private (`10.10.0.118`, `10.10.0.48`, `10.10.0.154`), so the remaining
blocker is the external/private-network firewall path for Cilium VXLAN UDP
8472. The complete command/file/egress integration gate remains unaccepted
until that path is opened or the CNI is repaired.

## Lab networking limitation

The normal Pod-networking Tenant Server rollout was reverted to a lab-only
host-network/private-IP fallback after observing:

- Service DNS queries from `kfa-test` timing out against `10.96.0.10`;
- cross-node Pod-IP reachability failing for some replicas;
- NodePort access from the control-plane host failing while private node IP
  access worked.

The repository production manifest remains normal Pod networking so that the
default-deny NetworkPolicy and ClusterIP design are enforceable in a healthy
CNI environment. The live lab currently uses static private endpoints:

```text
OpenSandbox Server: 10.10.0.154:30083 (lab-only NodePort workaround)
KFA:                10.10.0.48:30082
Tenant Server:      hostNetwork, NodePort 30081
```

Before applying `k8s/tenant-server-networkpolicy.yaml` or the KFA production
overlay, repair and verify Cilium Service/DNS routing. Applying those policies
to the current lab would risk cutting off authentication, PostgreSQL, metrics,
and upstream traffic.

## Remaining live acceptance gates

1. Allow Cilium VXLAN UDP/8472 between `10.10.0.0/24` nodes (or use a
   verified CNI transport), then rerun the normal Pod-networking Tenant Server
   rollout and Service/CoreDNS checks.
2. Rerun command, upload/download, egress allow, egress reset, and cleanup
   integration after cross-node sandbox Pod traffic is verified.
3. Apply HTTPS Ingress only after a TLS Secret is provisioned and verify the
   public path with the ingress smoke test.
4. Configure the PostgreSQL object-store destination and Secret, wait for a
   completed `Backup`, then perform a restore into a disposable namespace.
5. Apply the KFA production overlay and prove three replicas can reach the
   private API-server endpoint before calling KFA HA accepted.
