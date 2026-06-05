#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KUBECONFIG_PATH="${KUBECONFIG_PATH:-$ROOT_DIR/generated/kubeconfig}"
RESOURCE_GROUP="${RESOURCE_GROUP:-rg-azure-k3s-lab-tf}"
LOCATION="${LOCATION:-eastus}"
NAMESPACE="${NAMESPACE:-csi-lab}"
RUN_ID="${RUN_ID:-$(date +%H%M%S)}"
STORAGE_ACCOUNT="${STORAGE_ACCOUNT:-stopenqq$(date +%m%d%H%M%S | tail -c 9)}"
FILE_SHARE="${FILE_SHARE:-openshell-csi-share}"
PV_NAME="${PV_NAME:-pv-azurefile-${RUN_ID}}"
PVC_NAME="${PVC_NAME:-pvc-azurefile-${RUN_ID}}"
POD_NAME="${POD_NAME:-azurefile-pod-${RUN_ID}}"
SANDBOX_NAME="${SANDBOX_NAME:-azurefile-sandbox-${RUN_ID}}"
ARTIFACT_DIR="${ARTIFACT_DIR:-$ROOT_DIR/testing/raw/azurefile-csi-$(date +%s)}"

mkdir -p "$ARTIFACT_DIR"

log() {
  printf '[azurefile-csi] %s\n' "$*"
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

cleanup_existing() {
  kubectl_k -n "$NAMESPACE" delete pod "$POD_NAME" --ignore-not-found >/dev/null 2>&1 || true
  kubectl_k -n "$NAMESPACE" delete sandbox "$SANDBOX_NAME" --ignore-not-found >/dev/null 2>&1 || true
  kubectl_k -n "$NAMESPACE" delete pvc "$PVC_NAME" --ignore-not-found >/dev/null 2>&1 || true
  kubectl_k delete pv "$PV_NAME" --ignore-not-found >/dev/null 2>&1 || true
}

need az
need kubectl
need helm

log "installing Azure File CSI driver if needed"
helm repo add azurefile-csi-driver https://raw.githubusercontent.com/kubernetes-sigs/azurefile-csi-driver/master/charts >/dev/null 2>&1 || true
helm --kubeconfig "$KUBECONFIG_PATH" upgrade --install azurefile-csi-driver azurefile-csi-driver/azurefile-csi-driver \
  --namespace kube-system \
  --version 1.35.3 >/dev/null

kubectl_k -n kube-system wait --for=condition=Ready pod -l app.kubernetes.io/instance=azurefile-csi-driver --timeout=180s >/dev/null
kubectl_k get pods -n kube-system -l app.kubernetes.io/instance=azurefile-csi-driver -o wide > "$ARTIFACT_DIR/csi-driver-pods.txt"

log "ensuring storage account and file share exist"
az storage account show -g "$RESOURCE_GROUP" -n "$STORAGE_ACCOUNT" >/dev/null 2>&1 || \
  az storage account create -g "$RESOURCE_GROUP" -n "$STORAGE_ACCOUNT" -l "$LOCATION" \
    --sku Standard_LRS --kind StorageV2 --allow-blob-public-access false --min-tls-version TLS1_2 >/dev/null

ACCOUNT_KEY="$(az storage account keys list -g "$RESOURCE_GROUP" -n "$STORAGE_ACCOUNT" --query '[0].value' -o tsv)"
az storage share-rm show --resource-group "$RESOURCE_GROUP" --storage-account "$STORAGE_ACCOUNT" --name "$FILE_SHARE" >/dev/null 2>&1 || \
  az storage share-rm create --resource-group "$RESOURCE_GROUP" --storage-account "$STORAGE_ACCOUNT" --name "$FILE_SHARE" --quota 100 >/dev/null

log "resetting test namespace resources"
kubectl_k create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl_k apply -f - >/dev/null
cleanup_existing

log "creating Azure File secret, PV, PVC, Pod and Sandbox"
cat <<EOF | kubectl_k apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: azure-secret
  namespace: ${NAMESPACE}
type: Opaque
stringData:
  azurestorageaccountname: ${STORAGE_ACCOUNT}
  azurestorageaccountkey: ${ACCOUNT_KEY}
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: ${PV_NAME}
  annotations:
    pv.kubernetes.io/provisioned-by: file.csi.azure.com
spec:
  capacity:
    storage: 10Gi
  accessModes:
    - ReadWriteMany
  persistentVolumeReclaimPolicy: Retain
  storageClassName: azurefile-csi-static
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
  csi:
    driver: file.csi.azure.com
    volumeHandle: ${RESOURCE_GROUP}#${STORAGE_ACCOUNT}#${FILE_SHARE}
    volumeAttributes:
      resourceGroup: ${RESOURCE_GROUP}
      storageAccount: ${STORAGE_ACCOUNT}
      shareName: ${FILE_SHARE}
    nodeStageSecretRef:
      name: azure-secret
      namespace: ${NAMESPACE}
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${PVC_NAME}
  namespace: ${NAMESPACE}
spec:
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 10Gi
  storageClassName: azurefile-csi-static
  volumeName: ${PV_NAME}
---
apiVersion: v1
kind: Pod
metadata:
  name: ${POD_NAME}
  namespace: ${NAMESPACE}
spec:
  restartPolicy: Never
  containers:
    - name: shell
      image: alpine:3.20
      command: ["/bin/sh", "-c", "sleep 3600"]
      volumeMounts:
        - name: azure-share
          mountPath: /mnt/azurefile
  volumes:
    - name: azure-share
      persistentVolumeClaim:
        claimName: ${PVC_NAME}
---
apiVersion: agents.x-k8s.io/v1alpha1
kind: Sandbox
metadata:
  name: ${SANDBOX_NAME}
  namespace: ${NAMESPACE}
spec:
  podTemplate:
    metadata:
      labels:
        app: ${SANDBOX_NAME}
    spec:
      containers:
        - name: shell
          image: alpine:3.20
          command: ["/bin/sh", "-c", "sleep 3600"]
          volumeMounts:
            - name: azure-share
              mountPath: /mnt/azurefile
      volumes:
        - name: azure-share
          persistentVolumeClaim:
            claimName: ${PVC_NAME}
EOF

kubectl_k wait --for=condition=Ready pod/"$POD_NAME" -n "$NAMESPACE" --timeout=180s >/dev/null
kubectl_k wait --for=condition=Ready sandbox/"$SANDBOX_NAME" -n "$NAMESPACE" --timeout=180s >/dev/null

log "running cross-workload read/write verification"
kubectl_k exec -n "$NAMESPACE" "$POD_NAME" -- /bin/sh -c \
  'echo "from-pod" > /mnt/azurefile/proof.txt && cat /mnt/azurefile/proof.txt && df -h /mnt/azurefile && mount | grep /mnt/azurefile' \
  | tee "$ARTIFACT_DIR/pod-proof.txt"

kubectl_k exec -n "$NAMESPACE" "$SANDBOX_NAME" -- /bin/sh -c \
  'cat /mnt/azurefile/proof.txt && echo "from-sandbox" >> /mnt/azurefile/proof.txt && cat /mnt/azurefile/proof.txt && df -h /mnt/azurefile && mount | grep /mnt/azurefile' \
  | tee "$ARTIFACT_DIR/sandbox-proof.txt"

kubectl_k exec -n "$NAMESPACE" "$POD_NAME" -- /bin/sh -c 'cat /mnt/azurefile/proof.txt' \
  | tee "$ARTIFACT_DIR/pod-final.txt"

log "capturing Kubernetes objects"
kubectl_k get pv "$PV_NAME" -o yaml > "$ARTIFACT_DIR/pv.yaml"
kubectl_k -n "$NAMESPACE" get pvc "$PVC_NAME" -o yaml > "$ARTIFACT_DIR/pvc.yaml"
kubectl_k -n "$NAMESPACE" get pod "$POD_NAME" -o yaml > "$ARTIFACT_DIR/pod.yaml"
kubectl_k -n "$NAMESPACE" get sandbox "$SANDBOX_NAME" -o yaml > "$ARTIFACT_DIR/sandbox.yaml"
kubectl_k -n "$NAMESPACE" describe pod "$POD_NAME" > "$ARTIFACT_DIR/pod.describe.txt"
kubectl_k -n "$NAMESPACE" describe sandbox "$SANDBOX_NAME" > "$ARTIFACT_DIR/sandbox.describe.txt"

printf '%s\n' "$STORAGE_ACCOUNT" > "$ARTIFACT_DIR/storage-account.txt"
printf '%s\n' "$FILE_SHARE" > "$ARTIFACT_DIR/file-share.txt"

log "verification completed"
log "artifact directory: $ARTIFACT_DIR"
