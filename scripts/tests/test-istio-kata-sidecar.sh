#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK_DIR="$(mktemp -d)"
FAKE_BIN="$WORK_DIR/bin"
FAKE_KUBECTL="$FAKE_BIN/kubectl"
OUT_JSON="$WORK_DIR/out.json"
MANIFEST_PATH="$WORK_DIR/manifest.yaml"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

mkdir -p "$FAKE_BIN"

cat >"$FAKE_KUBECTL" <<EOF
#!/usr/bin/env bash
set -euo pipefail

cmd="\$*"

case "\$cmd" in
  *" get runtimeclass kata"*)
    exit 0
    ;;
  *" apply -f -"*)
    cat >"$MANIFEST_PATH"
    exit 0
    ;;
  *" rollout status "*)
    exit 0
    ;;
  *" get pod -l app=echo-"*" jsonpath={.items[0].metadata.name}"*)
    echo "server-pod"
    exit 0
    ;;
  *" get pod -l app=curl-"*" jsonpath={.items[0].metadata.name}"*)
    echo "client-pod"
    exit 0
    ;;
  *" get pod -l app=echo-"*" jsonpath={.items[0].spec.containers[*].name}"*)
    echo "echo"
    exit 0
    ;;
  *" get pod -l app=curl-"*" jsonpath={.items[0].spec.containers[*].name}"*)
    echo "curl"
    exit 0
    ;;
  *" get pod -l app=echo-"*" jsonpath={.items[0].spec.initContainers[*].name}"*)
    echo "istio-init istio-proxy"
    exit 0
    ;;
  *" get pod -l app=curl-"*" jsonpath={.items[0].spec.initContainers[*].name}"*)
    echo "istio-init istio-proxy"
    exit 0
    ;;
  *" get pod -l app=echo-"*"annotations.sidecar"* )
    echo '{"containers":["istio-proxy"]}'
    exit 0
    ;;
  *" get pod -l app=curl-"*"annotations.sidecar"* )
    echo '{"containers":["istio-proxy"]}'
    exit 0
    ;;
  *" get pod server-pod -o jsonpath={.spec.runtimeClassName}"*)
    echo "kata"
    exit 0
    ;;
  *" get pod client-pod -o jsonpath={.spec.runtimeClassName}"*)
    echo "kata"
    exit 0
    ;;
  *" get pod server-pod -o jsonpath={.spec.nodeName}"*)
    echo "worker-1"
    exit 0
    ;;
  *" get pod client-pod -o jsonpath={.spec.nodeName}"*)
    echo "worker-2"
    exit 0
    ;;
  *" exec deploy/"*" -c curl -- curl -fsS "*)
    echo "kata-mesh-ok"
    exit 0
    ;;
  *" delete ns "*)
    exit 0
    ;;
esac

echo "unexpected kubectl call: \$cmd" >&2
exit 1
EOF

chmod +x "$FAKE_KUBECTL"

PATH="$FAKE_BIN:$PATH" "$ROOT_DIR/scripts/tests/istio-kata-sidecar.sh" dummy-kubeconfig demo-stack >"$OUT_JSON"

python3 - <<'PY' "$MANIFEST_PATH" "$OUT_JSON"
import json
import sys
from pathlib import Path

manifest = Path(sys.argv[1]).read_text()
payload = json.loads(Path(sys.argv[2]).read_text())

assert manifest.count("runtimeClassName: kata") == 2, manifest
assert payload["status"] == "pass", payload
assert payload["details"]["response"] == "kata-mesh-ok", payload
assert payload["details"]["serverRuntimeClass"] == "kata", payload
assert payload["details"]["clientRuntimeClass"] == "kata", payload
PY

echo "test-istio-kata-sidecar: ok"
