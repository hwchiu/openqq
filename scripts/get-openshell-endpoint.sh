#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KUBECONFIG_PATH="${KUBECONFIG_PATH:-$ROOT_DIR/generated/kubeconfig}"
TERRAFORM_DIR="${TERRAFORM_DIR:-$ROOT_DIR/terraform}"
SERVICE_NAMESPACE="${SERVICE_NAMESPACE:-openshell}"
SERVICE_NAME="${SERVICE_NAME:-openshell}"

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl is required" >&2
  exit 1
fi

if ! command -v terraform >/dev/null 2>&1; then
  echo "terraform is required" >&2
  exit 1
fi

control_plane_ip="$(terraform -chdir="$TERRAFORM_DIR" output -raw control_plane_public_ip)"
node_port="$(kubectl --kubeconfig "$KUBECONFIG_PATH" -n "$SERVICE_NAMESPACE" get svc "$SERVICE_NAME" -o jsonpath='{.spec.ports[0].nodePort}')"

printf 'http://%s:%s\n' "$control_plane_ip" "$node_port"
