#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK_DIR="$(mktemp -d)"
FAKE_BIN="$WORK_DIR/bin"
FAKE_KUBECTL="$FAKE_BIN/kubectl"
OUT_JSON="$WORK_DIR/out.json"
MANIFEST_1="$WORK_DIR/apply-1.yaml"
MANIFEST_2="$WORK_DIR/apply-2.yaml"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

mkdir -p "$FAKE_BIN"

cat >"$FAKE_KUBECTL" <<EOF
#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="$WORK_DIR/state"
mkdir -p "\$STATE_DIR"
cmd="\$*"

if [[ "\$cmd" == *" apply -f -"* ]]; then
  count_file="\$STATE_DIR/apply_count"
  count=0
  if [[ -f "\$count_file" ]]; then
    count="\$(cat "\$count_file")"
  fi
  count=\$((count + 1))
  printf '%s' "\$count" > "\$count_file"
  cat > "$WORK_DIR/apply-\${count}.yaml"
  exit 0
fi

case "\$cmd" in
  *" get runtimeclass kata"*)
    exit 0
    ;;
  *" wait --for=condition=Ready "*)
    exit 0
    ;;
  *" get pod server -o jsonpath={.spec.runtimeClassName}"*)
    echo "kata"
    exit 0
    ;;
  *" get pod allowed -o jsonpath={.spec.runtimeClassName}"*)
    echo "kata"
    exit 0
    ;;
  *" get pod blocked -o jsonpath={.spec.runtimeClassName}"*)
    echo "kata"
    exit 0
    ;;
  *" get pod server -o jsonpath={.spec.nodeName}"*)
    echo "worker-1"
    exit 0
    ;;
  *" get pod allowed -o jsonpath={.spec.nodeName}"*)
    echo "worker-2"
    exit 0
    ;;
  *" get pod blocked -o jsonpath={.spec.nodeName}"*)
    echo "worker-1"
    exit 0
    ;;
  *" exec allowed -- curl -fsS --max-time 5 "*)
    echo "np-ok"
    exit 0
    ;;
  *" exec blocked -- curl -fsS --max-time 5 "*)
    calls_file="\$STATE_DIR/blocked_calls"
    calls=0
    if [[ -f "\$calls_file" ]]; then
      calls="\$(cat "\$calls_file")"
    fi
    calls=\$((calls + 1))
    printf '%s' "\$calls" > "\$calls_file"
    if [[ "\$calls" -eq 1 ]]; then
      echo "np-ok"
      exit 0
    fi
    echo "curl: (7) Failed to connect" >&2
    exit 7
    ;;
  *" delete ns "*)
    exit 0
    ;;
esac

echo "unexpected kubectl call: \$cmd" >&2
exit 1
EOF

chmod +x "$FAKE_KUBECTL"

PATH="$FAKE_BIN:$PATH" "$ROOT_DIR/scripts/tests/networkpolicy-kata-ingress.sh" dummy-kubeconfig demo-stack >"$OUT_JSON"

python3 - <<'PY' "$MANIFEST_1" "$MANIFEST_2" "$OUT_JSON"
import json
import sys
from pathlib import Path

manifest1 = Path(sys.argv[1]).read_text()
manifest2 = Path(sys.argv[2]).read_text()
payload = json.loads(Path(sys.argv[3]).read_text())

assert manifest1.count("runtimeClassName: kata") == 3, manifest1
assert "kind: Service" in manifest1, manifest1
assert "name: allowed" in manifest1, manifest1
assert "name: blocked" in manifest1, manifest1
assert "kind: NetworkPolicy" in manifest2, manifest2
assert "policyTypes:" in manifest2 and "- Ingress" in manifest2, manifest2
assert "access: allowed" in manifest2, manifest2

assert payload["status"] == "pass", payload
assert payload["details"]["baselineAllowed"] == "np-ok", payload
assert payload["details"]["baselineBlocked"] == "np-ok", payload
assert payload["details"]["allowedAfterPolicy"] == "np-ok", payload
assert payload["details"]["blockedExitCode"] == 7, payload
assert "curl: (7)" in payload["details"]["blockedStderr"], payload
assert payload["details"]["serverRuntimeClass"] == "kata", payload
assert payload["details"]["allowedRuntimeClass"] == "kata", payload
assert payload["details"]["blockedRuntimeClass"] == "kata", payload
PY

echo "test-networkpolicy-kata-ingress: ok"
