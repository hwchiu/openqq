#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CATALOG="$ROOT_DIR/testing/matrix/catalog.json"
RESULTS_DIR="$ROOT_DIR/testing/results/latest"
PUBLISH_RESULTS="${PUBLISH_RESULTS:-false}"
mkdir -p "$RESULTS_DIR"

command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo "kubectl is required" >&2; exit 1; }

stack_ids=($(jq -r '.stacks[].id' "$CATALOG"))
test_ids=($(jq -r '.tests[].id' "$CATALOG"))

for stack in "${stack_ids[@]}"; do
  mkdir -p "$RESULTS_DIR/$stack"
  kubeconfig="$ROOT_DIR/generated/stacks/$stack/kubeconfig"
  for test_id in "${test_ids[@]}"; do
    test_json="$(jq -c --arg id "$test_id" '.tests[] | select(.id==$id)' "$CATALOG")"
    runner="$(jq -r '.runner' <<<"$test_json")"
    applies_to="$(jq -c '.appliesTo' <<<"$test_json")"
    out_file="$RESULTS_DIR/$stack/$test_id.json"

    if ! jq -e --arg stack "$stack" 'index("all") or index($stack)' <<<"$applies_to" >/dev/null; then
      jq -n --arg stack "$stack" --arg test "$test_id" '{stack:$stack,test:$test,status:"na",summary:"This test does not apply to this environment"}' > "$out_file"
      continue
    fi

    if [[ ! -f "$kubeconfig" ]]; then
      jq -n --arg stack "$stack" --arg test "$test_id" '{stack:$stack,test:$test,status:"pending",summary:"kubeconfig missing; install this stack first"}' > "$out_file"
      continue
    fi

    set +e
    raw="$($ROOT_DIR/$runner "$kubeconfig" "$stack" 2>&1)"
    rc=$?
    set -e

    if jq -e . >/dev/null 2>&1 <<<"$raw"; then
      jq --arg stack "$stack" --arg test "$test_id" '. + {stack:$stack,test:$test}' <<<"$raw" > "$out_file"
    else
      if [[ $rc -eq 0 ]]; then
        jq -n --arg stack "$stack" --arg test "$test_id" --arg raw "$raw" '{stack:$stack,test:$test,status:"pass",summary:$raw}' > "$out_file"
      else
        jq -n --arg stack "$stack" --arg test "$test_id" --arg raw "$raw" '{stack:$stack,test:$test,status:"fail",summary:"Runner exited non-zero",details:{stderr:$raw}}' > "$out_file"
      fi
    fi
  done
done

python3 - <<'PY'
import json
from pathlib import Path
root = Path("testing/results/latest")
catalog = json.loads(Path("testing/matrix/catalog.json").read_text())
out = {
    "generatedAt": __import__("datetime").datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
    "source": "testing/results/latest",
    "stacks": catalog["stacks"],
    "tests": catalog["tests"],
    "results": {}
}
for stack in catalog["stacks"]:
    sid = stack["id"]
    out["results"][sid] = {}
    for test in catalog["tests"]:
      tid = test["id"]
      path = root / sid / f"{tid}.json"
      out["results"][sid][tid] = json.loads(path.read_text()) if path.exists() else {"stack": sid, "test": tid, "status": "pending", "summary": "No result file generated"}
Path("testing/results/latest/comparison-matrix.json").write_text(json.dumps(out, indent=2, ensure_ascii=False) + "\n")
PY

if [[ "$PUBLISH_RESULTS" == "true" ]]; then
  cp "$RESULTS_DIR/comparison-matrix.json" "$ROOT_DIR/docs/data/comparison-matrix.json"
fi

echo "$RESULTS_DIR/comparison-matrix.json"
