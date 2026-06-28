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
ARTIFACT_DIR="${ARTIFACT_DIR:-$ROOT_DIR/records/raw/$(date +%F)/kata-azurefile-csi-nfs-$(date +%s)}"

RUN_ID="$(date +%s)"
STATIC_NS="kata-fs-nfs-${RUN_ID}"
DYNAMIC_NS="kata-fs-dyn-${RUN_ID}"
STATIC_PV="pv-kata-nfs-${RUN_ID}"
STATIC_PVC="pvc-kata-nfs-${RUN_ID}"
DYNAMIC_SC="azurefile-csi-nfs-dyn-${RUN_ID}"
DYNAMIC_PVC="pvc-dyn-nfs-${RUN_ID}"
STORAGE_ACCOUNT="${STORAGE_ACCOUNT:-stkatanfs$(date +%m%d%H%M%S | tail -c 7)}"
FILE_SHARE="${FILE_SHARE:-kata-nfs-share}"

STATIC_CREATED=false
DYNAMIC_CREATED=false
STORAGE_CREATED=false

log() {
  printf '[kata-azurefile-csi-nfs] %s\n' "$*" >&2
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

  if [[ "$DYNAMIC_CREATED" == "true" && -f "$ARTIFACT_DIR/dynamic-manifest.yaml" ]]; then
    kubectl_k delete -f "$ARTIFACT_DIR/dynamic-manifest.yaml" --ignore-not-found >/dev/null 2>&1 || true
  fi

  if [[ "$STATIC_CREATED" == "true" && -f "$ARTIFACT_DIR/static-manifest.yaml" ]]; then
    kubectl_k delete -f "$ARTIFACT_DIR/static-manifest.yaml" --ignore-not-found >/dev/null 2>&1 || true
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

VNET_NAME="${VNET_NAME:-$(az network vnet list -g "$RESOURCE_GROUP" --query '[0].name' -o tsv)}"
SUBNET_NAME="${SUBNET_NAME:-$(az network vnet subnet list -g "$RESOURCE_GROUP" --vnet-name "$VNET_NAME" --query '[0].name' -o tsv)}"

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

log "preparing Azure Files NFS backend"
az network vnet subnet show -g "$RESOURCE_GROUP" --vnet-name "$VNET_NAME" -n "$SUBNET_NAME" -o json >"$ARTIFACT_DIR/subnet-before.json"
az network vnet subnet update -g "$RESOURCE_GROUP" --vnet-name "$VNET_NAME" -n "$SUBNET_NAME" --service-endpoints Microsoft.Storage -o json >"$ARTIFACT_DIR/subnet-after-update.json"

az storage account create -g "$RESOURCE_GROUP" -n "$STORAGE_ACCOUNT" -l "$LOCATION" \
  --sku Premium_LRS \
  --kind FileStorage \
  --https-only false \
  --allow-blob-public-access false \
  --public-network-access Enabled \
  -o json >"$ARTIFACT_DIR/storage-account-create.json"
STORAGE_CREATED=true

printf '%s\n' "$STORAGE_ACCOUNT" >"$ARTIFACT_DIR/storage-account.txt"
printf '%s\n' "$FILE_SHARE" >"$ARTIFACT_DIR/file-share.txt"

az storage account network-rule add -g "$RESOURCE_GROUP" --account-name "$STORAGE_ACCOUNT" --vnet-name "$VNET_NAME" --subnet "$SUBNET_NAME" -o json >"$ARTIFACT_DIR/storage-account-network-rule-add.json"
az storage account show -g "$RESOURCE_GROUP" -n "$STORAGE_ACCOUNT" -o json >"$ARTIFACT_DIR/storage-account.json"
az storage account network-rule list -g "$RESOURCE_GROUP" --account-name "$STORAGE_ACCOUNT" -o json >"$ARTIFACT_DIR/storage-account-network-rules.json"
az storage account update -g "$RESOURCE_GROUP" -n "$STORAGE_ACCOUNT" --default-action Deny --bypass AzureServices -o json >"$ARTIFACT_DIR/storage-account-default-deny.json"
az storage account show -g "$RESOURCE_GROUP" -n "$STORAGE_ACCOUNT" -o json >"$ARTIFACT_DIR/storage-account-post-deny.json"
az storage account network-rule list -g "$RESOURCE_GROUP" --account-name "$STORAGE_ACCOUNT" -o json >"$ARTIFACT_DIR/storage-account-network-rules-post-deny.json"
az storage share-rm create -g "$RESOURCE_GROUP" --storage-account "$STORAGE_ACCOUNT" -n "$FILE_SHARE" --enabled-protocols NFS --quota 100 --root-squash NoRootSquash -o json >"$ARTIFACT_DIR/file-share-create.json"
az storage share-rm show -g "$RESOURCE_GROUP" --storage-account "$STORAGE_ACCOUNT" -n "$FILE_SHARE" -o json >"$ARTIFACT_DIR/file-share.json"

log "running static CSI mount test in Kata pods"
cat >"$ARTIFACT_DIR/static-manifest.yaml" <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: ${STATIC_NS}
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: ${STATIC_PV}
  annotations:
    pv.kubernetes.io/provisioned-by: file.csi.azure.com
spec:
  capacity:
    storage: 100Gi
  accessModes:
    - ReadWriteMany
  persistentVolumeReclaimPolicy: Retain
  storageClassName: azurefile-csi-nfs-static
  mountOptions:
    - nconnect=4
    - noresvport
    - actimeo=30
  csi:
    driver: file.csi.azure.com
    volumeHandle: ${RESOURCE_GROUP}#${STORAGE_ACCOUNT}#${FILE_SHARE}
    volumeAttributes:
      resourceGroup: ${RESOURCE_GROUP}
      storageAccount: ${STORAGE_ACCOUNT}
      shareName: ${FILE_SHARE}
      protocol: nfs
      mountPermissions: "0777"
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${STATIC_PVC}
  namespace: ${STATIC_NS}
spec:
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 100Gi
  storageClassName: azurefile-csi-nfs-static
  volumeName: ${STATIC_PV}
---
apiVersion: v1
kind: Pod
metadata:
  name: writer
  namespace: ${STATIC_NS}
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
        claimName: ${STATIC_PVC}
---
apiVersion: v1
kind: Pod
metadata:
  name: reader
  namespace: ${STATIC_NS}
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
        claimName: ${STATIC_PVC}
EOF

STATIC_CREATED=true
printf '%s\n' "$STATIC_NS" >"$ARTIFACT_DIR/namespace.txt"
printf '%s\n' "$STATIC_PV" >"$ARTIFACT_DIR/pv-name.txt"
printf '%s\n' "$STATIC_PVC" >"$ARTIFACT_DIR/pvc-name.txt"

kubectl_k apply -f "$ARTIFACT_DIR/static-manifest.yaml" >"$ARTIFACT_DIR/static-apply.txt"
kubectl_k wait --for=jsonpath='{.status.phase}'=Bound pvc/"$STATIC_PVC" -n "$STATIC_NS" --timeout=180s >"$ARTIFACT_DIR/pvc-wait.txt"
kubectl_k wait --for=condition=Ready pod/writer -n "$STATIC_NS" --timeout=300s >"$ARTIFACT_DIR/writer-ready.txt"
kubectl_k wait --for=condition=Ready pod/reader -n "$STATIC_NS" --timeout=300s >"$ARTIFACT_DIR/reader-ready.txt"
kubectl_k get pod -n "$STATIC_NS" -o wide >"$ARTIFACT_DIR/pods-wide.txt"
kubectl_k get pv "$STATIC_PV" -o yaml >"$ARTIFACT_DIR/pv.yaml"
kubectl_k -n "$STATIC_NS" get pvc "$STATIC_PVC" -o yaml >"$ARTIFACT_DIR/pvc.yaml"
kubectl_k -n "$STATIC_NS" get pod writer -o yaml >"$ARTIFACT_DIR/writer-pod.yaml"
kubectl_k -n "$STATIC_NS" get pod reader -o yaml >"$ARTIFACT_DIR/reader-pod.yaml"
kubectl_k -n "$STATIC_NS" describe pod writer >"$ARTIFACT_DIR/writer.describe.txt"
kubectl_k -n "$STATIC_NS" describe pod reader >"$ARTIFACT_DIR/reader.describe.txt"
kubectl_k get events -n "$STATIC_NS" --sort-by=.lastTimestamp >"$ARTIFACT_DIR/events.txt"

WRITER_CMD='uname -a; cat /proc/version; echo "--- mount"; mount | grep /mnt/azurefile; echo "--- proc-mounts"; cat /proc/mounts | grep /mnt/azurefile; echo "--- df"; df -h /mnt/azurefile; echo "--- fstype"; stat -f -c %T /mnt/azurefile; echo "from-writer $(date -Iseconds)" > /mnt/azurefile/proof.txt; sync; echo "--- content"; cat /mnt/azurefile/proof.txt'
READER_CMD='uname -a; cat /proc/version; echo "--- mount"; mount | grep /mnt/azurefile; echo "--- proc-mounts"; cat /proc/mounts | grep /mnt/azurefile; echo "--- df"; df -h /mnt/azurefile; echo "--- fstype"; stat -f -c %T /mnt/azurefile; echo "--- content-before"; cat /mnt/azurefile/proof.txt; echo "from-reader $(date -Iseconds)" >> /mnt/azurefile/proof.txt; sync; echo "--- content-after"; cat /mnt/azurefile/proof.txt'

kubectl_k exec -n "$STATIC_NS" writer -- /bin/sh -lc "$WRITER_CMD" >"$ARTIFACT_DIR/writer-exec.txt"
kubectl_k exec -n "$STATIC_NS" reader -- /bin/sh -lc "$READER_CMD" >"$ARTIFACT_DIR/reader-exec.txt"
kubectl_k exec -n "$STATIC_NS" writer -- /bin/sh -lc 'cat /mnt/azurefile/proof.txt' >"$ARTIFACT_DIR/final-proof.txt"
sleep "$CROSS_NODE_SETTLE_SECONDS"
kubectl_k exec -n "$STATIC_NS" writer -- /bin/sh -lc 'echo "--- writer-after-delay"; cat /mnt/azurefile/proof.txt' >"$ARTIFACT_DIR/final-proof-after-35s.txt"

WRITER_SID="$(ssh_safe "${SSH_USER}@${WRITER_HOST}" "sudo crictl pods -q --name writer | head -n1")"
READER_SID="$(ssh_safe "${SSH_USER}@${READER_HOST}" "sudo crictl pods -q --name reader | head -n1")"
printf '%s\n' "$WRITER_SID" >"$ARTIFACT_DIR/writer-sandbox-id.txt"
printf '%s\n' "$READER_SID" >"$ARTIFACT_DIR/reader-sandbox-id.txt"
ssh_safe "${SSH_USER}@${WRITER_HOST}" "sudo crictl inspectp ${WRITER_SID}" >"$ARTIFACT_DIR/writer-crictl-inspectp.json"
ssh_safe "${SSH_USER}@${READER_HOST}" "sudo crictl inspectp ${READER_SID}" >"$ARTIFACT_DIR/reader-crictl-inspectp.json"
ssh_safe "${SSH_USER}@${WRITER_HOST}" "sudo sh -lc 'ps -ef | egrep \"${WRITER_SID}|containerd-shim-kata-v2|qemu-system-x86_64|virtiofsd\" | grep ${WRITER_SID}'" >"$ARTIFACT_DIR/writer-kata-processes.txt"
ssh_safe "${SSH_USER}@${READER_HOST}" "sudo sh -lc 'ps -ef | egrep \"${READER_SID}|containerd-shim-kata-v2|qemu-system-x86_64|virtiofsd\" | grep ${READER_SID}'" >"$ARTIFACT_DIR/reader-kata-processes.txt"
ssh_safe "${SSH_USER}@${WRITER_HOST}" "sudo sh -lc 'mount | grep -E \"${STORAGE_ACCOUNT}|${FILE_SHARE}\"'" >"$ARTIFACT_DIR/worker-1-nfs-mounts.txt"
ssh_safe "${SSH_USER}@${READER_HOST}" "sudo sh -lc 'mount | grep -E \"${STORAGE_ACCOUNT}|${FILE_SHARE}\"'" >"$ARTIFACT_DIR/worker-2-nfs-mounts.txt"
ssh_safe "${SSH_USER}@${WRITER_HOST}" "sudo journalctl -u crio --since '15 minutes ago' | grep -E 'writer|${WRITER_SID}' || true" >"$ARTIFACT_DIR/writer-crio-journal.txt"
ssh_safe "${SSH_USER}@${READER_HOST}" "sudo journalctl -u crio --since '15 minutes ago' | grep -E 'reader|${READER_SID}' || true" >"$ARTIFACT_DIR/reader-crio-journal.txt"

W1_CSI_POD="$(kubectl_k -n kube-system get pod -l app=csi-azurefile-node --field-selector spec.nodeName="${WRITER_NODE}" -o jsonpath='{.items[0].metadata.name}')"
W2_CSI_POD="$(kubectl_k -n kube-system get pod -l app=csi-azurefile-node --field-selector spec.nodeName="${READER_NODE}" -o jsonpath='{.items[0].metadata.name}')"
printf '%s\n' "$W1_CSI_POD" >"$ARTIFACT_DIR/worker-1-csi-pod.txt"
printf '%s\n' "$W2_CSI_POD" >"$ARTIFACT_DIR/worker-2-csi-pod.txt"
kubectl_k -n kube-system logs "$W1_CSI_POD" -c azurefile --since=15m | grep -E "NodeStageVolume|NodePublishVolume|${STORAGE_ACCOUNT}|${FILE_SHARE}|${STATIC_PV}|${STATIC_NS}" >"$ARTIFACT_DIR/worker-1-csi-logs.txt" || true
kubectl_k -n kube-system logs "$W2_CSI_POD" -c azurefile --since=15m | grep -E "NodeStageVolume|NodePublishVolume|${STORAGE_ACCOUNT}|${FILE_SHARE}|${STATIC_PV}|${STATIC_NS}" >"$ARTIFACT_DIR/worker-2-csi-logs.txt" || true

log "running dynamic CSI provisioning check"
cat >"$ARTIFACT_DIR/dynamic-manifest.yaml" <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: ${DYNAMIC_NS}
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ${DYNAMIC_SC}
provisioner: file.csi.azure.com
parameters:
  protocol: nfs
  skuName: Premium_LRS
  resourceGroup: ${RESOURCE_GROUP}
  storageAccount: ${STORAGE_ACCOUNT}
  shareNamePrefix: dynkata
reclaimPolicy: Delete
volumeBindingMode: Immediate
allowVolumeExpansion: true
mountOptions:
  - nconnect=4
  - noresvport
  - actimeo=30
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${DYNAMIC_PVC}
  namespace: ${DYNAMIC_NS}
spec:
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 100Gi
  storageClassName: ${DYNAMIC_SC}
---
apiVersion: v1
kind: Pod
metadata:
  name: dyn-kata
  namespace: ${DYNAMIC_NS}
spec:
  runtimeClassName: kata
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
        claimName: ${DYNAMIC_PVC}
EOF

DYNAMIC_CREATED=true
printf '%s\n' "$DYNAMIC_NS" >"$ARTIFACT_DIR/dynamic-namespace.txt"
printf '%s\n' "$DYNAMIC_SC" >"$ARTIFACT_DIR/dynamic-sc.txt"
printf '%s\n' "$DYNAMIC_PVC" >"$ARTIFACT_DIR/dynamic-pvc.txt"
printf '%s\n' "dyn-kata" >"$ARTIFACT_DIR/dynamic-pod.txt"

kubectl_k apply -f "$ARTIFACT_DIR/dynamic-manifest.yaml" >"$ARTIFACT_DIR/dynamic-apply.txt"

set +e
kubectl_k wait --for=jsonpath='{.status.phase}'=Bound pvc/"$DYNAMIC_PVC" -n "$DYNAMIC_NS" --timeout=120s >"$ARTIFACT_DIR/dynamic-pvc-wait.txt" 2>"$ARTIFACT_DIR/dynamic-pvc-wait.err"
DYNAMIC_PVC_WAIT_RC=$?
kubectl_k wait --for=condition=Ready pod/dyn-kata -n "$DYNAMIC_NS" --timeout=60s >"$ARTIFACT_DIR/dynamic-pod-wait.txt" 2>"$ARTIFACT_DIR/dynamic-pod-wait.err"
DYNAMIC_POD_WAIT_RC=$?
set -e

kubectl_k get sc "$DYNAMIC_SC" -o yaml >"$ARTIFACT_DIR/dynamic-storageclass.yaml"
kubectl_k -n "$DYNAMIC_NS" get pvc "$DYNAMIC_PVC" -o yaml >"$ARTIFACT_DIR/dynamic-pvc.yaml"
kubectl_k -n "$DYNAMIC_NS" describe pvc "$DYNAMIC_PVC" >"$ARTIFACT_DIR/dynamic-pvc.describe.txt"
kubectl_k -n "$DYNAMIC_NS" get pod dyn-kata -o yaml >"$ARTIFACT_DIR/dynamic-pod.yaml"
kubectl_k -n "$DYNAMIC_NS" describe pod dyn-kata >"$ARTIFACT_DIR/dynamic-pod.describe.txt"
kubectl_k get events -n "$DYNAMIC_NS" --sort-by=.lastTimestamp >"$ARTIFACT_DIR/dynamic-events.txt"

mapfile -t CONTROLLER_PODS < <(kubectl_k -n kube-system get pod -l app=csi-azurefile-controller -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')
for pod in "${CONTROLLER_PODS[@]}"; do
  [[ -n "$pod" ]] || continue
  kubectl_k -n kube-system describe pod "$pod" >"$ARTIFACT_DIR/${pod}.describe.txt"
  kubectl_k -n kube-system logs "$pod" -c azurefile >"$ARTIFACT_DIR/${pod}.current.log" 2>/dev/null || true
  kubectl_k -n kube-system logs "$pod" -c azurefile --previous >"$ARTIFACT_DIR/${pod}.previous.log" 2>/dev/null || true
done

kubectl_k delete -f "$ARTIFACT_DIR/dynamic-manifest.yaml" --ignore-not-found >"$ARTIFACT_DIR/dynamic-delete.txt"
DYNAMIC_CREATED=false

kubectl_k -n kube-system rollout restart deploy/csi-azurefile-controller >"$ARTIFACT_DIR/controller-rollout-restart.txt"
kubectl_k -n kube-system rollout status deploy/csi-azurefile-controller --timeout=240s >"$ARTIFACT_DIR/controller-rollout-status-after-restart.txt"
kubectl_k get pods -n kube-system -l app.kubernetes.io/instance=azurefile-csi-driver -o wide >"$ARTIFACT_DIR/csi-driver-pods-final.txt"
kubectl_k get ds,deploy -n kube-system -l app.kubernetes.io/instance=azurefile-csi-driver -o wide >"$ARTIFACT_DIR/csi-driver-workloads-final.txt"
kubectl_k get csidriver,csinode >"$ARTIFACT_DIR/csi-objects-final.txt"
kubectl_k get sc,pv,pvc -A >"$ARTIFACT_DIR/storage-objects-final.txt"

if [[ "$PRESERVE_TEST_RESOURCES" != "true" ]]; then
  kubectl_k delete -f "$ARTIFACT_DIR/static-manifest.yaml" --ignore-not-found >"$ARTIFACT_DIR/static-delete.txt"
  STATIC_CREATED=false
  az storage account delete -g "$RESOURCE_GROUP" -n "$STORAGE_ACCOUNT" -y
  STORAGE_CREATED=false
  az storage account show -g "$RESOURCE_GROUP" -n "$STORAGE_ACCOUNT" >"$ARTIFACT_DIR/storage-account-post-delete.txt" 2>&1 || true
fi

STATIC_GUEST_MOUNT="$(sed -n '/--- mount/{n;p;}' "$ARTIFACT_DIR/writer-exec.txt" | head -n1)"
STATIC_HOST_MOUNT="$(sed -n '1p' "$ARTIFACT_DIR/worker-1-nfs-mounts.txt")"
STATIC_FINAL_DELAY="$(tail -n +2 "$ARTIFACT_DIR/final-proof-after-35s.txt" | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
STATIC_WRITER_RUNTIME="$(rg -o '"io.kubernetes.cri-o.RuntimeHandler": "[^"]+"' "$ARTIFACT_DIR/writer-crictl-inspectp.json" | head -n1 | sed 's/.*: \"//; s/\"$//')"
STATIC_READER_RUNTIME="$(rg -o '"io.kubernetes.cri-o.RuntimeHandler": "[^"]+"' "$ARTIFACT_DIR/reader-crictl-inspectp.json" | head -n1 | sed 's/.*: \"//; s/\"$//')"

STATIC_STATUS="fail"
if [[ "$STATIC_GUEST_MOUNT" == *"virtiofs"* && "$STATIC_HOST_MOUNT" == *"type nfs4"* && "$STATIC_WRITER_RUNTIME" == "kata" && "$STATIC_READER_RUNTIME" == "kata" && "$STATIC_FINAL_DELAY" == *"from-writer"* && "$STATIC_FINAL_DELAY" == *"from-reader"* ]]; then
  STATIC_STATUS="pass"
fi

DYNAMIC_PANIC=false
while IFS= read -r file; do
  [[ -n "$file" ]] || continue
  if rg -q 'panic: runtime error|updateSubnetServiceEndpoints|CreateVolume' "$file"; then
    DYNAMIC_PANIC=true
    break
  fi
done < <(find "$ARTIFACT_DIR" -maxdepth 1 -name 'csi-azurefile-controller-*.previous.log' | sort)

DYNAMIC_STATUS="pass"
if [[ "$DYNAMIC_PVC_WAIT_RC" -ne 0 || "$DYNAMIC_POD_WAIT_RC" -ne 0 || "$DYNAMIC_PANIC" == "true" ]]; then
  DYNAMIC_STATUS="fail"
fi

OVERALL_STATUS="fail"
SUMMARY="Azure Files NFS CSI test failed before a stable Kata mount result was established"
if [[ "$STATIC_STATUS" == "pass" && "$DYNAMIC_STATUS" == "fail" ]]; then
  OVERALL_STATUS="provisional"
  SUMMARY="Static Azure Files NFS CSI mount worked in Kata pods; dynamic provisioning failed and crashed the controller without Azure cloud config"
elif [[ "$STATIC_STATUS" == "pass" && "$DYNAMIC_STATUS" == "pass" ]]; then
  OVERALL_STATUS="pass"
  SUMMARY="Static and dynamic Azure Files NFS CSI both worked in Kata pods"
elif [[ "$STATIC_STATUS" == "pass" ]]; then
  OVERALL_STATUS="provisional"
  SUMMARY="Static Azure Files NFS CSI mount worked in Kata pods, but dynamic provisioning result was incomplete"
fi

jq -n \
  --arg status "$OVERALL_STATUS" \
  --arg summary "$SUMMARY" \
  --arg stack "$STACK_NAME" \
  --arg resourceGroup "$RESOURCE_GROUP" \
  --arg location "$LOCATION" \
  --arg driverVersion "$AZUREFILE_CSI_DRIVER_VERSION" \
  --arg artifactDir "$ARTIFACT_DIR" \
  --arg storageAccount "$STORAGE_ACCOUNT" \
  --arg fileShare "$FILE_SHARE" \
  --arg writerNode "$WRITER_NODE" \
  --arg readerNode "$READER_NODE" \
  --arg writerHost "$WRITER_HOST" \
  --arg readerHost "$READER_HOST" \
  --arg staticStatus "$STATIC_STATUS" \
  --arg staticGuestMount "$STATIC_GUEST_MOUNT" \
  --arg staticHostMount "$STATIC_HOST_MOUNT" \
  --arg staticWriterRuntime "$STATIC_WRITER_RUNTIME" \
  --arg staticReaderRuntime "$STATIC_READER_RUNTIME" \
  --arg staticFinalDelay "$STATIC_FINAL_DELAY" \
  --arg dynamicStatus "$DYNAMIC_STATUS" \
  --arg dynamicNamespace "$DYNAMIC_NS" \
  --arg dynamicStorageClass "$DYNAMIC_SC" \
  --arg dynamicPvc "$DYNAMIC_PVC" \
  --arg dynamicPvcStatus "$(grep '^Status:' "$ARTIFACT_DIR/dynamic-pvc.describe.txt" | awk '{print $2}')" \
  --arg dynamicPodScheduling "$(grep 'FailedScheduling' "$ARTIFACT_DIR/dynamic-pod.describe.txt" | tail -n1 | sed 's/^[[:space:]]*//')" \
  --arg dynamicPvcWaitError "$(cat "$ARTIFACT_DIR/dynamic-pvc-wait.err")" \
  --arg dynamicPodWaitError "$(cat "$ARTIFACT_DIR/dynamic-pod-wait.err")" \
  --argjson dynamicPvcWaitRc "$DYNAMIC_PVC_WAIT_RC" \
  --argjson dynamicPodWaitRc "$DYNAMIC_POD_WAIT_RC" \
  --argjson dynamicPanic "$DYNAMIC_PANIC" \
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
      storageAccount: $storageAccount,
      fileShare: $fileShare,
      static: {
        status: $staticStatus,
        writerNode: $writerNode,
        readerNode: $readerNode,
        writerHost: $writerHost,
        readerHost: $readerHost,
        writerRuntimeHandler: $staticWriterRuntime,
        readerRuntimeHandler: $staticReaderRuntime,
        guestMount: $staticGuestMount,
        hostMount: $staticHostMount,
        crossNodeVisibleAfterSeconds: $crossNodeSettleSeconds,
        finalContentAfterDelay: $staticFinalDelay
      },
      dynamic: {
        status: $dynamicStatus,
        namespace: $dynamicNamespace,
        storageClass: $dynamicStorageClass,
        pvc: $dynamicPvc,
        pvcStatus: $dynamicPvcStatus,
        pvcWaitRc: $dynamicPvcWaitRc,
        podWaitRc: $dynamicPodWaitRc,
        podScheduling: $dynamicPodScheduling,
        pvcWaitError: $dynamicPvcWaitError,
        podWaitError: $dynamicPodWaitError,
        controllerPanicObserved: $dynamicPanic
      }
    }
  }' | tee "$ARTIFACT_DIR/kata-azurefile-csi-nfs.json"
