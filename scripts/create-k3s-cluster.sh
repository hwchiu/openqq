#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib-cluster.sh"

create_network() {
  log "Creating resource group"
  az_safe group create --name "$AZURE_RESOURCE_GROUP" --location "$AZURE_REGION" >/dev/null

  log "Creating virtual network and subnet"
  az_safe network vnet create \
    --resource-group "$AZURE_RESOURCE_GROUP" \
    --name "$AZURE_VNET_NAME" \
    --address-prefix "$AZURE_VNET_CIDR" \
    --subnet-name "$AZURE_SUBNET_NAME" \
    --subnet-prefix "$AZURE_SUBNET_CIDR" >/dev/null

  log "Creating network security group"
  az_safe network nsg create \
    --resource-group "$AZURE_RESOURCE_GROUP" \
    --name "$AZURE_NSG_NAME" >/dev/null

  log "Allowing SSH and Kubernetes API access"
  az_safe network nsg rule create \
    --resource-group "$AZURE_RESOURCE_GROUP" \
    --nsg-name "$AZURE_NSG_NAME" \
    --name allow-ssh \
    --priority 1000 \
    --access Allow \
    --protocol Tcp \
    --direction Inbound \
    --destination-port-ranges 22 >/dev/null

  az_safe network nsg rule create \
    --resource-group "$AZURE_RESOURCE_GROUP" \
    --nsg-name "$AZURE_NSG_NAME" \
    --name allow-k8s-api \
    --priority 1010 \
    --access Allow \
    --protocol Tcp \
    --direction Inbound \
    --destination-port-ranges 6443 >/dev/null
}

create_vm() {
  local name="$1"

  log "Creating VM $name"
  az_safe vm create \
    --resource-group "$AZURE_RESOURCE_GROUP" \
    --name "$name" \
    --image Ubuntu2204 \
    --size "$AZURE_VM_SIZE" \
    --admin-username "$AZURE_ADMIN_USERNAME" \
    --ssh-key-values "$AZURE_SSH_PUBLIC_KEY_PATH" \
    --vnet-name "$AZURE_VNET_NAME" \
    --subnet "$AZURE_SUBNET_NAME" \
    --nsg "$AZURE_NSG_NAME" \
    --public-ip-sku Standard >/dev/null
}

install_server() {
  local host="$1"
  local key_path="$2"

  log "Installing k3s server on $host"
  ssh_safe -i "$key_path" "$AZURE_ADMIN_USERNAME@$host" \
    "curl -sfL https://get.k3s.io | sh -s - server --write-kubeconfig-mode 644 --tls-san $host --cluster-cidr $K3S_CLUSTER_CIDR --service-cidr $K3S_SERVICE_CIDR"
}

install_worker() {
  local host="$1"
  local key_path="$2"
  local server_ip="$3"
  local token="$4"

  log "Installing k3s agent on $host"
  ssh_safe -i "$key_path" "$AZURE_ADMIN_USERNAME@$host" \
    "curl -sfL https://get.k3s.io | K3S_URL=https://$server_ip:6443 K3S_TOKEN=$token sh -"
}

main() {
  cluster_preflight
  write_cluster_metadata

  local key_path
  key_path="$(default_private_key)"

  create_network
  create_vm "$CONTROL_PLANE_NAME"
  create_vm "$WORKER1_NAME"
  create_vm "$WORKER2_NAME"

  local cp_public_ip cp_private_ip worker1_public_ip worker2_public_ip token
  cp_public_ip="$(get_public_ip "$CONTROL_PLANE_NAME")"
  cp_private_ip="$(get_private_ip "$CONTROL_PLANE_NAME")"
  worker1_public_ip="$(get_public_ip "$WORKER1_NAME")"
  worker2_public_ip="$(get_public_ip "$WORKER2_NAME")"

  log "Waiting for SSH on control plane"
  wait_for_ssh "$cp_public_ip" "$key_path"
  install_server "$cp_public_ip" "$key_path"

  log "Reading k3s node token"
  token="$(ssh_safe -i "$key_path" "$AZURE_ADMIN_USERNAME@$cp_public_ip" 'sudo cat /var/lib/rancher/k3s/server/node-token')"

  log "Waiting for SSH on worker 1"
  wait_for_ssh "$worker1_public_ip" "$key_path"
  install_worker "$worker1_public_ip" "$key_path" "$cp_private_ip" "$token"

  log "Waiting for SSH on worker 2"
  wait_for_ssh "$worker2_public_ip" "$key_path"
  install_worker "$worker2_public_ip" "$key_path" "$cp_private_ip" "$token"

  "$SCRIPT_DIR/fetch-kubeconfig.sh"
  "$SCRIPT_DIR/kubectl-status.sh"

  cat <<EOF
[INFO] Cluster creation completed
[INFO] Control plane public IP: $cp_public_ip
[INFO] Worker 1 public IP: $worker1_public_ip
[INFO] Worker 2 public IP: $worker2_public_ip
[INFO] Kubeconfig path: $ROOT_DIR/generated/kubeconfig
EOF
}

main "$@"
