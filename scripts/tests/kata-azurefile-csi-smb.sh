#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEFAULT_KUBECONFIG="$ROOT_DIR/generated/stacks/k3s-kata-134/kubeconfig"
DEFAULT_TF_DIR="$ROOT_DIR/terraform/stacks/k3s-kata-134"
if [[ ! -f "$DEFAULT_KUBECONFIG" ]]; then
  DEFAULT_KUBECONFIG="$ROOT_DIR/generated/kubeconfig"
fi
if [[ ! -d "$DEFAULT_TF_DIR" ]]; then
  DEFAULT_TF_DIR="$ROOT_DIR/terraform"
fi
KUBECONFIG_PATH="${1:-${KUBECONFIG_PATH:-$DEFAULT_KUBECONFIG}}"
TF_DIR="${2:-${TF_DIR:-$DEFAULT_TF_DIR}}"
STACK_NAME="${3:-${STACK_NAME:-$(basename "$TF_DIR")}}"
SSH_KEY_PATH="${AZURE_SSH_PRIVATE_KEY_PATH:-$HOME/.ssh/id_ed25519}"
AZUREFILE_CSI_DRIVER_VERSION="${AZUREFILE_CSI_DRIVER_VERSION:-1.35.4}"
CROSS_NODE_SETTLE_SECONDS="${CROSS_NODE_SETTLE_SECONDS:-35}"
PRESERVE_TEST_RESOURCES="${PRESERVE_TEST_RESOURCES:-false}"
ARTIFACT_DIR="${ARTIFACT_DIR:-$ROOT_DIR/records/raw/$(date +%F)/kata-azurefile-csi-smb-$(date +%s)}"
STORAGE_SKU="${STORAGE_SKU:-Standard_LRS}"
STORAGE_KIND="${STORAGE_KIND:-StorageV2}"

RUN_ID="$(date +%s)"
TEST_NS="kata-fs-smb-${RUN_ID}"
TEST_SC="azurefile-csi-smb-${RUN_ID}"
TEST_PVC="pvc-kata-smb-${RUN_ID}"
STORAGE_ACCOUNT="${STORAGE_ACCOUNT:-stkatasmb$(date +%m%d%H%M%S | tail -c 7)}"

TEST_CREATED=false
STORAGE_CREATED=false

log() {
  printf '[kata-azurefile-csi-smb] %s\n' "$*" >&2
}

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing required command: $1" >&2
    exit 1
  }
}

kubectl_k() {
  kubectl --kubeconfig "$KUBECONFIG_PATH" "$@"
}

ssh_safe() {
  ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "$SSH_KEY_PATH" "$@"
}

cleanup() {
  if [[ "$PRESERVE_TEST_RESOURCES" == "true" ]]; then
    return 0
  fi

  if [[ "$TEST_CREATED" == "true" && -f "$ARTIFACT_DIR/workloads.yaml" ]]; then
    kubectl_k delete -f "$ARTIFACT_DIR/workloads.yaml" --ignore-not-found >/dev/null 2>&1 || true
    kubectl_k delete namespace "$TEST_NS" --ignore-not-found --wait=false >/dev/null 2>&1 || true
  fi

  if [[ "$STORAGE_CREATED" == "true" ]]; then
    az storage account delete -g "$RESOURCE_GROUP" -n "$STORAGE_ACCOUNT" -y >/dev/null 2>&1 || true
  fi
}

trap cleanup EXIT

need az
need helm
need jq
need kubectl
need rg
need ssh
need terraform

[[ -f "$KUBECONFIG_PATH" ]] || {
  echo "kubeconfig not found: $KUBECONFIG_PATH" >&2
  exit 1
}
[[ -f "$SSH_KEY_PATH" ]] || {
  echo "ssh key not found: $SSH_KEY_PATH" >&2
  exit 1
}
[[ -d "$TF_DIR" ]] || {
  echo "terraform stack directory not found: $TF_DIR" >&2
  exit 1
}

mkdir -p "$ARTIFACT_DIR"

TF_JSON="$(terraform -chdir="$TF_DIR" output -json)"
RESOURCE_GROUP="${RESOURCE_GROUP:-$(printf '%s' "$TF_JSON" | jq -r '.resource_group_name.value')}"
SSH_USER="${SSH_USER:-$(printf '%s' "$TF_JSON" | jq -r '.admin_username.value')}"
LOCATION="${LOCATION:-$(az group show -n "$RESOURCE_GROUP" --query location -o tsv)}"

declare -A WORKER_IPS=()
while IFS=' ' read -r node ip; do
  [[ -n "$node" && -n "$ip" ]] || continue
  WORKER_IPS["$node"]="$ip"
done < <(printf '%s' "$TF_JSON" | jq -r '.worker_public_ips.value | to_entries[] | "\(.key) \(.value)"')

mapfile -t WORKER_NODES < <(
  kubectl_k get nodes -o json | jq -r '
    .items[]
    | select(
        (.metadata.labels["node-role.kubernetes.io/control-plane"] | not)
        and (.metadata.labels["node-role.kubernetes.io/master"] | not)
      )
    | .metadata.name
  '
)

if [[ "${#WORKER_NODES[@]}" -lt 2 ]]; then
  echo "expected at least two worker nodes" >&2
  exit 1
fi

WRITER_NODE="${WRITER_NODE:-${WORKER_NODES[0]}}"
READER_NODE="${READER_NODE:-${WORKER_NODES[1]}}"
WRITER_HOST="${WORKER_IPS[$WRITER_NODE]:-}"
READER_HOST="${WORKER_IPS[$READER_NODE]:-}"

if [[ -z "$WRITER_HOST" || -z "$READER_HOST" ]]; then
  echo "could not resolve worker public IPs from terraform output" >&2
  exit 1
fi

log "installing Azure File CSI driver"
helm repo add azurefile-csi-driver https://raw.githubusercontent.com/kubernetes-sigs/azurefile-csi-driver/master/charts >/dev/null 2>&1 || true
helm repo update >/dev/null 2>&1
helm --kubeconfig "$KUBECONFIG_PATH" upgrade --install azurefile-csi-driver azurefile-csi-driver/azurefile-csi-driver \
  --namespace kube-system \
  --version "$AZUREFILE_CSI_DRIVER_VERSION" >"$ARTIFACT_DIR/helm-install.txt"

kubectl_k -n kube-system rollout status ds/csi-azurefile-node --timeout=240s >"$ARTIFACT_DIR/driver-node-rollout.txt"
kubectl_k -n kube-system rollout status deploy/csi-azurefile-controller --timeout=240s >"$ARTIFACT_DIR/driver-controller-rollout.txt"
kubectl_k get pods -n kube-system -l app.kubernetes.io/instance=azurefile-csi-driver -o wide >"$ARTIFACT_DIR/csi-driver-pods-install.txt"
kubectl_k get ds,deploy -n kube-system -l app.kubernetes.io/instance=azurefile-csi-driver -o wide >"$ARTIFACT_DIR/csi-driver-workloads-install.txt"
kubectl_k get csidriver,csinode >"$ARTIFACT_DIR/csi-objects-install.txt"

log "preparing Azure Files SMB backend"
az storage account create -g "$RESOURCE_GROUP" -n "$STORAGE_ACCOUNT" -l "$LOCATION" \
  --sku "$STORAGE_SKU" \
  --kind "$STORAGE_KIND" \
  --https-only true \
  --allow-blob-public-access false \
  --public-network-access Enabled \
  -o json >"$ARTIFACT_DIR/storage-account-create.json"
STORAGE_CREATED=true

STORAGE_KEY="$(az storage account keys list -g "$RESOURCE_GROUP" -n "$STORAGE_ACCOUNT" --query '[0].value' -o tsv)"
az storage account show -g "$RESOURCE_GROUP" -n "$STORAGE_ACCOUNT" -o json >"$ARTIFACT_DIR/storage-account.json"
printf '%s\n' "$STORAGE_ACCOUNT" >"$ARTIFACT_DIR/storage-account.txt"
printf '%s\n' "$STORAGE_SKU" >"$ARTIFACT_DIR/storage-sku.txt"
printf '%s\n' "$STORAGE_KIND" >"$ARTIFACT_DIR/storage-kind.txt"

log "creating namespace, secret, and dynamic StorageClass"
kubectl_k create namespace "$TEST_NS" >"$ARTIFACT_DIR/namespace-create.txt"
kubectl_k -n "$TEST_NS" create secret generic azure-secret \
  --from-literal "azurestorageaccountname=${STORAGE_ACCOUNT}" \
  --from-literal "azurestorageaccountkey=${STORAGE_KEY}" \
  --type Opaque >"$ARTIFACT_DIR/secret-create.txt"
kubectl_k -n "$TEST_NS" get secret azure-secret -o json \
  | jq '.data = {"azurestorageaccountname":"UkVEQUNURUQ=","azurestorageaccountkey":"UkVEQUNURUQ="}' \
  >"$ARTIFACT_DIR/secret-redacted.json"

cat >"$ARTIFACT_DIR/workloads.yaml" <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ${TEST_SC}
provisioner: file.csi.azure.com
allowVolumeExpansion: true
parameters:
  csi.storage.k8s.io/provisioner-secret-name: azure-secret
  csi.storage.k8s.io/provisioner-secret-namespace: ${TEST_NS}
  csi.storage.k8s.io/node-stage-secret-name: azure-secret
  csi.storage.k8s.io/node-stage-secret-namespace: ${TEST_NS}
  csi.storage.k8s.io/controller-expand-secret-name: azure-secret
  csi.storage.k8s.io/controller-expand-secret-namespace: ${TEST_NS}
mountOptions:
  - dir_mode=0777
  - file_mode=0777
  - uid=0
  - gid=0
  - mfsymlinks
  - cache=strict
  - nosharesock
  - actimeo=30
  - nobrl
reclaimPolicy: Delete
volumeBindingMode: Immediate
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${TEST_PVC}
  namespace: ${TEST_NS}
spec:
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 5Gi
  storageClassName: ${TEST_SC}
---
apiVersion: v1
kind: Pod
metadata:
  name: writer
  namespace: ${TEST_NS}
spec:
  runtimeClassName: kata
  nodeName: ${WRITER_NODE}
  restartPolicy: Never
  containers:
    - name: shell
      image: alpine:3.22
      command: ["/bin/sh", "-lc", "sleep 365d"]
      volumeMounts:
        - name: shared
          mountPath: /mnt/azurefile
  volumes:
    - name: shared
      persistentVolumeClaim:
        claimName: ${TEST_PVC}
---
apiVersion: v1
kind: Pod
metadata:
  name: reader
  namespace: ${TEST_NS}
spec:
  runtimeClassName: kata
  nodeName: ${READER_NODE}
  restartPolicy: Never
  containers:
    - name: shell
      image: alpine:3.22
      command: ["/bin/sh", "-lc", "sleep 365d"]
      volumeMounts:
        - name: shared
          mountPath: /mnt/azurefile
  volumes:
    - name: shared
      persistentVolumeClaim:
        claimName: ${TEST_PVC}
EOF

TEST_CREATED=true
printf '%s\n' "$TEST_NS" >"$ARTIFACT_DIR/test-namespace.txt"
printf '%s\n' "$TEST_SC" >"$ARTIFACT_DIR/test-sc.txt"
printf '%s\n' "$TEST_PVC" >"$ARTIFACT_DIR/test-pvc.txt"

kubectl_k apply -f "$ARTIFACT_DIR/workloads.yaml" >"$ARTIFACT_DIR/workloads-apply.txt"

set +e
kubectl_k wait --for=jsonpath='{.status.phase}'=Bound pvc/"$TEST_PVC" -n "$TEST_NS" --timeout=180s >"$ARTIFACT_DIR/pvc-wait.txt" 2>"$ARTIFACT_DIR/pvc-wait.err"
PVC_WAIT_RC=$?
kubectl_k wait --for=condition=Ready pod/writer pod/reader -n "$TEST_NS" --timeout=180s >"$ARTIFACT_DIR/pods-wait.txt" 2>"$ARTIFACT_DIR/pods-wait.err"
PODS_WAIT_RC=$?
set -e

kubectl_k get sc "$TEST_SC" -o yaml >"$ARTIFACT_DIR/storageclass.yaml"
kubectl_k -n "$TEST_NS" get pvc "$TEST_PVC" -o yaml >"$ARTIFACT_DIR/pvc.yaml"
kubectl_k -n "$TEST_NS" describe pvc "$TEST_PVC" >"$ARTIFACT_DIR/pvc.describe.txt"
kubectl_k -n "$TEST_NS" get pod writer -o yaml >"$ARTIFACT_DIR/writer-pod.yaml"
kubectl_k -n "$TEST_NS" describe pod writer >"$ARTIFACT_DIR/writer.describe.txt"
kubectl_k -n "$TEST_NS" get pod reader -o yaml >"$ARTIFACT_DIR/reader-pod.yaml"
kubectl_k -n "$TEST_NS" describe pod reader >"$ARTIFACT_DIR/reader.describe.txt"
kubectl_k get events -n "$TEST_NS" --sort-by=.lastTimestamp >"$ARTIFACT_DIR/events.txt"
kubectl_k get pods -n "$TEST_NS" -o wide >"$ARTIFACT_DIR/pods-wide.txt"
kubectl_k get sc,pv,pvc -A >"$ARTIFACT_DIR/storage-objects-before-cleanup.txt"

TEST_PV="$(kubectl_k -n "$TEST_NS" get pvc "$TEST_PVC" -o jsonpath='{.spec.volumeName}' 2>/dev/null || true)"
printf '%s\n' "$TEST_PV" >"$ARTIFACT_DIR/test-pv.txt"
if [[ -n "$TEST_PV" ]]; then
  kubectl_k get pv "$TEST_PV" -o yaml >"$ARTIFACT_DIR/pv.yaml"
fi

az storage share-rm list -g "$RESOURCE_GROUP" --storage-account "$STORAGE_ACCOUNT" -o json >"$ARTIFACT_DIR/storage-shares.json"

mapfile -t CONTROLLER_PODS < <(kubectl_k -n kube-system get pod -l app=csi-azurefile-controller -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')
for pod in "${CONTROLLER_PODS[@]}"; do
  [[ -n "$pod" ]] || continue
  kubectl_k -n kube-system describe pod "$pod" >"$ARTIFACT_DIR/${pod}.describe.txt"
  kubectl_k -n kube-system logs "$pod" -c azurefile >"$ARTIFACT_DIR/${pod}.current.log" 2>/dev/null || true
  kubectl_k -n kube-system logs "$pod" -c azurefile --previous >"$ARTIFACT_DIR/${pod}.previous.log" 2>/dev/null || true
done

WORKLOAD_STATUS="fail"
if [[ "$PVC_WAIT_RC" -eq 0 && "$PODS_WAIT_RC" -eq 0 ]]; then
  WORKLOAD_STATUS="pass"

  WRITER_CMD='uname -a; cat /proc/version; echo "--- mount"; mount | grep /mnt/azurefile; echo "--- proc-mounts"; cat /proc/mounts | grep /mnt/azurefile; echo "--- df"; df -h /mnt/azurefile; echo "from-writer $(date -Iseconds)" > /mnt/azurefile/proof.txt; sync; echo "--- content"; cat /mnt/azurefile/proof.txt'
  READER_CMD='uname -a; cat /proc/version; echo "--- mount"; mount | grep /mnt/azurefile; echo "--- proc-mounts"; cat /proc/mounts | grep /mnt/azurefile; echo "--- df"; df -h /mnt/azurefile; echo "--- content-before"; cat /mnt/azurefile/proof.txt; echo "from-reader $(date -Iseconds)" >> /mnt/azurefile/proof.txt; sync; echo "--- content-after"; cat /mnt/azurefile/proof.txt'

  kubectl_k exec -n "$TEST_NS" writer -- /bin/sh -lc "$WRITER_CMD" >"$ARTIFACT_DIR/writer-exec.txt"
  kubectl_k exec -n "$TEST_NS" reader -- /bin/sh -lc "$READER_CMD" >"$ARTIFACT_DIR/reader-exec.txt"
  kubectl_k exec -n "$TEST_NS" writer -- /bin/sh -lc 'echo "--- writer-after-immediate"; cat /mnt/azurefile/proof.txt' >"$ARTIFACT_DIR/final-proof.txt"
  sleep "$CROSS_NODE_SETTLE_SECONDS"
  kubectl_k exec -n "$TEST_NS" writer -- /bin/sh -lc 'echo "--- writer-after-delay"; cat /mnt/azurefile/proof.txt' >"$ARTIFACT_DIR/final-proof-after-35s.txt"

  WRITER_UID="$(kubectl_k -n "$TEST_NS" get pod writer -o jsonpath='{.metadata.uid}')"
  READER_UID="$(kubectl_k -n "$TEST_NS" get pod reader -o jsonpath='{.metadata.uid}')"
  WRITER_SID="$(ssh_safe "${SSH_USER}@${WRITER_HOST}" "sudo crictl pods -q --label io.kubernetes.pod.uid=${WRITER_UID} | head -n1")"
  READER_SID="$(ssh_safe "${SSH_USER}@${READER_HOST}" "sudo crictl pods -q --label io.kubernetes.pod.uid=${READER_UID} | head -n1")"
  printf '%s\n' "$WRITER_SID" >"$ARTIFACT_DIR/writer-sandbox-id.txt"
  printf '%s\n' "$READER_SID" >"$ARTIFACT_DIR/reader-sandbox-id.txt"
  ssh_safe "${SSH_USER}@${WRITER_HOST}" "sudo crictl inspectp ${WRITER_SID}" >"$ARTIFACT_DIR/writer-crictl-inspectp.json"
  ssh_safe "${SSH_USER}@${READER_HOST}" "sudo crictl inspectp ${READER_SID}" >"$ARTIFACT_DIR/reader-crictl-inspectp.json"
  ssh_safe "${SSH_USER}@${WRITER_HOST}" "sudo sh -lc 'ps -ef | egrep \"${WRITER_SID}|containerd-shim-kata-v2|qemu-system-x86_64|virtiofsd\" | grep ${WRITER_SID}'" >"$ARTIFACT_DIR/writer-kata-processes.txt"
  ssh_safe "${SSH_USER}@${READER_HOST}" "sudo sh -lc 'ps -ef | egrep \"${READER_SID}|containerd-shim-kata-v2|qemu-system-x86_64|virtiofsd\" | grep ${READER_SID}'" >"$ARTIFACT_DIR/reader-kata-processes.txt"
  ssh_safe "${SSH_USER}@${WRITER_HOST}" "sudo sh -lc 'mount | grep -E \"${STORAGE_ACCOUNT}|${TEST_PV}\"'" >"$ARTIFACT_DIR/worker-1-cifs-mounts.txt"
  ssh_safe "${SSH_USER}@${READER_HOST}" "sudo sh -lc 'mount | grep -E \"${STORAGE_ACCOUNT}|${TEST_PV}\"'" >"$ARTIFACT_DIR/worker-2-cifs-mounts.txt"
  ssh_safe "${SSH_USER}@${WRITER_HOST}" "sudo journalctl -u crio --since '15 minutes ago' | grep -E 'writer|${WRITER_SID}' || true" >"$ARTIFACT_DIR/writer-crio-journal.txt"
  ssh_safe "${SSH_USER}@${READER_HOST}" "sudo journalctl -u crio --since '15 minutes ago' | grep -E 'reader|${READER_SID}' || true" >"$ARTIFACT_DIR/reader-crio-journal.txt"

  W1_CSI_POD="$(kubectl_k -n kube-system get pod -l app=csi-azurefile-node --field-selector spec.nodeName="${WRITER_NODE}" -o jsonpath='{.items[0].metadata.name}')"
  W2_CSI_POD="$(kubectl_k -n kube-system get pod -l app=csi-azurefile-node --field-selector spec.nodeName="${READER_NODE}" -o jsonpath='{.items[0].metadata.name}')"
  printf '%s\n' "$W1_CSI_POD" >"$ARTIFACT_DIR/worker-1-csi-pod.txt"
  printf '%s\n' "$W2_CSI_POD" >"$ARTIFACT_DIR/worker-2-csi-pod.txt"
  kubectl_k -n kube-system logs "$W1_CSI_POD" -c azurefile --since=15m | grep -E "NodeStageVolume|NodePublishVolume|${STORAGE_ACCOUNT}|${TEST_PV}|${TEST_NS}" >"$ARTIFACT_DIR/worker-1-csi-logs.txt" || true
  kubectl_k -n kube-system logs "$W2_CSI_POD" -c azurefile --since=15m | grep -E "NodeStageVolume|NodePublishVolume|${STORAGE_ACCOUNT}|${TEST_PV}|${TEST_NS}" >"$ARTIFACT_DIR/worker-2-csi-logs.txt" || true
fi

kubectl_k get pods -n kube-system -l app.kubernetes.io/instance=azurefile-csi-driver -o wide >"$ARTIFACT_DIR/csi-driver-pods-final.txt"
kubectl_k get ds,deploy -n kube-system -l app.kubernetes.io/instance=azurefile-csi-driver -o wide >"$ARTIFACT_DIR/csi-driver-workloads-final.txt"
kubectl_k get csidriver,csinode >"$ARTIFACT_DIR/csi-objects-final.txt"

if [[ "$PRESERVE_TEST_RESOURCES" != "true" ]]; then
  kubectl_k delete -f "$ARTIFACT_DIR/workloads.yaml" --ignore-not-found >"$ARTIFACT_DIR/workloads-delete.txt"
  kubectl_k delete namespace "$TEST_NS" --ignore-not-found --wait=false >"$ARTIFACT_DIR/namespace-delete.txt" 2>&1 || true
  TEST_CREATED=false
  az storage account delete -g "$RESOURCE_GROUP" -n "$STORAGE_ACCOUNT" -y
  STORAGE_CREATED=false
  az storage account show -g "$RESOURCE_GROUP" -n "$STORAGE_ACCOUNT" >"$ARTIFACT_DIR/storage-account-post-delete.txt" 2>&1 || true
fi

PVC_STATUS="$(grep '^Status:' "$ARTIFACT_DIR/pvc.describe.txt" | awk '{print $2}')"
PVC_EVENTS="$(grep 'ProvisioningSucceeded' "$ARTIFACT_DIR/pvc.describe.txt" | tail -n1 | sed 's/^[[:space:]]*//')"
GUEST_MOUNT=""
HOST_MOUNT=""
WRITER_RUNTIME=""
READER_RUNTIME=""
FINAL_DELAY=""

if [[ "$WORKLOAD_STATUS" == "pass" ]]; then
  GUEST_MOUNT="$(sed -n '/--- mount/{n;p;}' "$ARTIFACT_DIR/writer-exec.txt" | head -n1)"
  HOST_MOUNT="$(sed -n '1p' "$ARTIFACT_DIR/worker-1-cifs-mounts.txt")"
  FINAL_DELAY="$(tail -n +2 "$ARTIFACT_DIR/final-proof-after-35s.txt" | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
  WRITER_RUNTIME="$(rg -o '"io.kubernetes.cri-o.RuntimeHandler": "[^"]+"' "$ARTIFACT_DIR/writer-crictl-inspectp.json" | head -n1 | sed 's/.*: \"//; s/\"$//')"
  READER_RUNTIME="$(rg -o '"io.kubernetes.cri-o.RuntimeHandler": "[^"]+"' "$ARTIFACT_DIR/reader-crictl-inspectp.json" | head -n1 | sed 's/.*: \"//; s/\"$//')"
fi

OVERALL_STATUS="fail"
SUMMARY="Azure Files SMB dynamic StorageClass test did not establish a stable Kata mount"
if [[ "$WORKLOAD_STATUS" == "pass" && "$PVC_STATUS" == "Bound" && "$GUEST_MOUNT" == *"virtiofs"* && "$HOST_MOUNT" == *"type cifs"* && "$WRITER_RUNTIME" == "kata" && "$READER_RUNTIME" == "kata" && "$FINAL_DELAY" == *"from-writer"* && "$FINAL_DELAY" == *"from-reader"* ]]; then
  OVERALL_STATUS="pass"
  SUMMARY="Azure Files SMB dynamic StorageClass provisioned successfully and mounted into Kata pods across two worker nodes"
fi

jq -n \
  --arg status "$OVERALL_STATUS" \
  --arg summary "$SUMMARY" \
  --arg stack "$STACK_NAME" \
  --arg resourceGroup "$RESOURCE_GROUP" \
  --arg location "$LOCATION" \
  --arg driverVersion "$AZUREFILE_CSI_DRIVER_VERSION" \
  --arg artifactDir "$ARTIFACT_DIR" \
  --arg storageType "Azure Files SMB via file.csi.azure.com" \
  --arg storageAccount "$STORAGE_ACCOUNT" \
  --arg storageSku "$STORAGE_SKU" \
  --arg storageKind "$STORAGE_KIND" \
  --arg namespace "$TEST_NS" \
  --arg storageClass "$TEST_SC" \
  --arg pvc "$TEST_PVC" \
  --arg pv "$TEST_PV" \
  --arg writerNode "$WRITER_NODE" \
  --arg readerNode "$READER_NODE" \
  --arg writerHost "$WRITER_HOST" \
  --arg readerHost "$READER_HOST" \
  --arg pvcStatus "$PVC_STATUS" \
  --arg pvcEvents "$PVC_EVENTS" \
  --arg guestMount "$GUEST_MOUNT" \
  --arg hostMount "$HOST_MOUNT" \
  --arg writerRuntimeHandler "$WRITER_RUNTIME" \
  --arg readerRuntimeHandler "$READER_RUNTIME" \
  --arg finalContentAfterDelay "$FINAL_DELAY" \
  --arg pvcWaitError "$(cat "$ARTIFACT_DIR/pvc-wait.err")" \
  --arg podsWaitError "$(cat "$ARTIFACT_DIR/pods-wait.err")" \
  --argjson pvcWaitRc "$PVC_WAIT_RC" \
  --argjson podsWaitRc "$PODS_WAIT_RC" \
  --argjson crossNodeSettleSeconds "$CROSS_NODE_SETTLE_SECONDS" \
  '{
    status: $status,
    summary: $summary,
    details: {
      stack: $stack,
      resourceGroup: $resourceGroup,
      location: $location,
      driverVersion: $driverVersion,
      artifactDir: $artifactDir,
      storageType: $storageType,
      storageAccount: $storageAccount,
      storageSku: $storageSku,
      storageKind: $storageKind,
      dynamic: {
        namespace: $namespace,
        storageClass: $storageClass,
        pvc: $pvc,
        pv: $pv,
        pvcStatus: $pvcStatus,
        pvcEvents: $pvcEvents,
        pvcWaitRc: $pvcWaitRc,
        podsWaitRc: $podsWaitRc,
        pvcWaitError: $pvcWaitError,
        podsWaitError: $podsWaitError
      },
      kata: {
        writerNode: $writerNode,
        readerNode: $readerNode,
        writerHost: $writerHost,
        readerHost: $readerHost,
        writerRuntimeHandler: $writerRuntimeHandler,
        readerRuntimeHandler: $readerRuntimeHandler,
        guestMount: $guestMount,
        hostMount: $hostMount,
        crossNodeSettleSeconds: $crossNodeSettleSeconds,
        finalContentAfterDelay: $finalContentAfterDelay
      }
    }
  }' | tee "$ARTIFACT_DIR/kata-azurefile-csi-smb.json"
