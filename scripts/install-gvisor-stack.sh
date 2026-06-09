#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STACK_NAME="${1:?usage: install-gvisor-stack.sh <stack-name>}"
# shellcheck source=scripts/lib-stack.sh
source "$ROOT_DIR/scripts/lib-stack.sh"

require_bin terraform
require_bin jq
require_bin kubectl

stack_dir="$(resolve_stack_dir "$STACK_NAME")"
admin_username="$(terraform -chdir="$stack_dir" output -raw admin_username)"
cp_public_ip="$(terraform -chdir="$stack_dir" output -raw control_plane_public_ip)"
worker_ips_json="$(terraform -chdir="$stack_dir" output -json worker_public_ips)"

REMOTE_SCRIPT="$(cat <<'REMOTE'
#!/usr/bin/env bash
set -euxo pipefail

if ! command -v runsc >/dev/null 2>&1; then
  curl -fsSL https://gvisor.dev/archive.key \
    | gpg --batch --yes --dearmor -o /usr/share/keyrings/gvisor-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/gvisor-archive-keyring.gpg] https://storage.googleapis.com/gvisor/releases release main" \
    > /etc/apt/sources.list.d/gvisor.list
  apt-get update -qq
  apt-get install -y runsc
fi

mkdir -p /etc/crio/crio.conf.d
install -d -m 1777 /run/runsc
CONMON_PATH="$(command -v conmon 2>/dev/null || echo /usr/libexec/crio/conmon)"
RUNSC_PATH="$(command -v runsc)"
cat > /etc/crio/crio.conf.d/10-runsc.conf <<CRIOCFG
[crio.runtime.runtimes.runsc]
runtime_path = "${RUNSC_PATH}"
runtime_type = "oci"
runtime_root = "/run/runsc"
privileged_without_host_devices = false
monitor_path = "${CONMON_PATH}"
CRIOCFG
cat > /etc/crio/crio.conf.d/20-gvisor-podsandbox.conf <<CRIOPODCFG
[crio.runtime]
drop_infra_ctr = false
CRIOPODCFG

FLANNEL_CONFLIST="/var/lib/rancher/k3s/agent/etc/cni/net.d/10-flannel.conflist"
if [[ -f "${FLANNEL_CONFLIST}" ]]; then
  python3 - "${FLANNEL_CONFLIST}" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
data = json.loads(path.read_text())
data["plugins"] = [plugin for plugin in data.get("plugins", []) if plugin.get("type") != "bandwidth"]
path.write_text(json.dumps(data, indent=2) + "\n")
PY
fi

systemctl restart crio
if systemctl list-unit-files | grep -q '^k3s.service'; then
  systemctl restart k3s
fi
if systemctl list-unit-files | grep -q '^k3s-agent.service'; then
  systemctl restart k3s-agent
fi
runsc --version
REMOTE
)"

for ip in "$cp_public_ip" $(jq -r '.[]' <<<"$worker_ips_json"); do
  wait_for_ssh "${admin_username}@${ip}"
  ssh_safe "${admin_username}@${ip}" "sudo bash -s" <<<"$REMOTE_SCRIPT"
done

KUBECONFIG_PATH="${KUBECONFIG_PATH:-$(fetch_kubeconfig_from_stack "$STACK_NAME")}"
kubectl --kubeconfig "$KUBECONFIG_PATH" apply -f "$ROOT_DIR/k8s/gvisor-runtimeclass.yaml"
