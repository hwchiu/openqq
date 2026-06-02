# Agent Sandbox Runbook

## Verify the controller

Check the CRD:

```bash
kubectl --kubeconfig generated/kubeconfig get crd sandboxes.agents.x-k8s.io
```

Check the controller:

```bash
kubectl --kubeconfig generated/kubeconfig get pods -n agent-sandbox-system
```

## Verify sandbox creation

Apply the smoke sandbox:

```bash
kubectl --kubeconfig generated/kubeconfig apply -f k8s/agent-sandbox-smoke.yaml
```

Verify the Sandbox object:

```bash
kubectl --kubeconfig generated/kubeconfig get sandbox sandbox-smoke
kubectl --kubeconfig generated/kubeconfig describe sandbox sandbox-smoke
```

Verify the backing pod:

```bash
kubectl --kubeconfig generated/kubeconfig get pod sandbox-smoke -o wide
kubectl --kubeconfig generated/kubeconfig exec sandbox-smoke -- /bin/sh -c 'echo ok'
```

Clean it up:

```bash
kubectl --kubeconfig generated/kubeconfig delete -f k8s/agent-sandbox-smoke.yaml
```

## Deploy MariaDB in a Sandbox

Apply:

```bash
kubectl --kubeconfig generated/kubeconfig apply -f k8s/agent-sandbox-mariadb.yaml
```

Verify:

```bash
kubectl --kubeconfig generated/kubeconfig get sandbox mariadb-sandbox
kubectl --kubeconfig generated/kubeconfig get pod mariadb-sandbox -o wide
kubectl --kubeconfig generated/kubeconfig get pvc
```

Check MariaDB from inside the pod:

```bash
kubectl --kubeconfig generated/kubeconfig exec mariadb-sandbox -- mariadb -uroot -pchange-me-root-password -e 'SELECT VERSION();'
```

## Notes

1. The current example uses inline passwords for simplicity. Replace them with a Secret for real use.
2. The current example does not expose MariaDB outside the cluster. Add a Service only if you actually need network access.
3. `Sandbox` supports `volumeClaimTemplates`, so the MariaDB data directory can persist across restarts.
