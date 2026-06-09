# Docs Visual Normalization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Normalize all root `docs/*.html` pages to the same visual system as `docs/index.html`, and update any filesystem-capability claims only after revalidating against the existing four live Azure environments.

**Architecture:** Keep each root docs page's current information architecture, but remove visual drift by consolidating hero, section, card, stat, CTA, and table treatments onto the same shared primitives already used by `docs/index.html`. For any capability-sensitive copy, recover kubeconfigs from the existing Azure control planes with `az vm run-command invoke`, run the relevant live validations against those clusters, then update docs and published matrix data from the observed results instead of from default-state assumptions.

**Tech Stack:** Static HTML, shared CSS in `docs/assets/reference.css`, shell scripts, Azure CLI, `kubectl`, `jq`

---

### Task 1: Recover Live Stack Kubeconfigs From Azure

**Files:**
- Create: `scripts/fetch-live-stack-kubeconfigs.sh`
- Modify: `scripts/lib-stack.sh`
- Test: `generated/stacks/k3s-gvisor/kubeconfig`
- Test: `generated/stacks/k3s-openshell-runc/kubeconfig`
- Test: `generated/stacks/k3s-openshell-gvisor/kubeconfig`
- Test: `generated/stacks/k3s-kubearmor-runc/kubeconfig`

- [ ] **Step 1: Write the failing probe**

```bash
./scripts/fetch-live-stack-kubeconfigs.sh
```

Expected: shell returns `No such file or directory` because the helper does not exist yet.

- [ ] **Step 2: Add Azure run-command kubeconfig recovery to `scripts/lib-stack.sh`**

```bash
fetch_kubeconfig_via_azure_run_command() {
  local stack_name="$1"
  local out_dir="$GENERATED_STACKS_DIR/$stack_name"
  local resource_group=""
  local control_plane_name="cp-0"
  local admin_username="${AZURE_ADMIN_USERNAME:-azureuser}"
  mkdir -p "$out_dir"

  case "$stack_name" in
    k3s-gvisor) resource_group="rg-k3s-gvisor" ;;
    k3s-openshell-runc) resource_group="rg-k3s-openshell-runc" ;;
    k3s-openshell-gvisor) resource_group="rg-k3s-openshell-gvisor" ;;
    k3s-kubearmor-runc) resource_group="rg-k3s-kubearmor-runc" ;;
    *) fail "Unknown live Azure stack: $stack_name" ;;
  esac

  require_bin az
  local cp_public_ip
  cp_public_ip="$(az vm show -d -g "$resource_group" -n "$control_plane_name" --query publicIps -o tsv)"
  [[ -n "$cp_public_ip" ]] || fail "No public IP found for $stack_name control plane"

  az vm run-command invoke \
    -g "$resource_group" \
    -n "$control_plane_name" \
    --command-id RunShellScript \
    --scripts 'sudo cat /etc/rancher/k3s/k3s.yaml' \
    --query 'value[0].message' \
    -o tsv \
    | sed -n '/^\[stdout\]$/,/^\[stderr\]$/p' \
    | sed '1d;$d' > "$out_dir/kubeconfig.raw"

  sed "s/127.0.0.1/$cp_public_ip/g" "$out_dir/kubeconfig.raw" > "$out_dir/kubeconfig"
  chmod 600 "$out_dir/kubeconfig"
  printf '%s\n' "$out_dir/kubeconfig"
}
```

- [ ] **Step 3: Create the stack bootstrap helper**

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/lib-stack.sh"

stacks=(
  k3s-gvisor
  k3s-openshell-runc
  k3s-openshell-gvisor
  k3s-kubearmor-runc
)

for stack in "${stacks[@]}"; do
  log "Recovering kubeconfig for $stack"
  fetch_kubeconfig_via_azure_run_command "$stack" >/dev/null
done

printf '%s\n' "$ROOT_DIR/generated/stacks"
```

- [ ] **Step 4: Run the helper and verify all four kubeconfigs exist**

Run:

```bash
./scripts/fetch-live-stack-kubeconfigs.sh
find generated/stacks -maxdepth 2 -name kubeconfig -type f | sort
```

Expected:

```text
generated/stacks/k3s-gvisor/kubeconfig
generated/stacks/k3s-kubearmor-runc/kubeconfig
generated/stacks/k3s-openshell-gvisor/kubeconfig
generated/stacks/k3s-openshell-runc/kubeconfig
```

- [ ] **Step 5: Validate the live kubeconfigs talk to the four running clusters**

Run:

```bash
for s in k3s-gvisor k3s-openshell-runc k3s-openshell-gvisor k3s-kubearmor-runc; do
  echo "=== $s ==="
  kubectl --kubeconfig "generated/stacks/$s/kubeconfig" get nodes -o wide
done
```

Expected: each stack shows `cp-0`, `worker-1`, and `worker-2` in `Ready` state.

- [ ] **Step 6: Commit**

```bash
git add scripts/lib-stack.sh scripts/fetch-live-stack-kubeconfigs.sh
git commit -m "feat: recover live stack kubeconfigs from azure"
```

### Task 2: Add Live KubeArmor Filesystem Write Validation

**Files:**
- Create: `k8s/kubearmor-block-etc-nginx-write.yaml`
- Create: `scripts/verify-kubearmor-filesystem.sh`
- Create: `scripts/tests/kubearmor-filesystem.sh`
- Modify: `testing/matrix/catalog.json`
- Test: `generated/stacks/k3s-kubearmor-runc/kubeconfig`

- [ ] **Step 1: Write the failing validation probe**

Run:

```bash
./scripts/tests/kubearmor-filesystem.sh generated/stacks/k3s-kubearmor-runc/kubeconfig k3s-kubearmor-runc
```

Expected: shell returns `No such file or directory` because the runner does not exist yet.

- [ ] **Step 2: Add a concrete write-block policy for the demo workload**

```yaml
apiVersion: security.kubearmor.com/v1
kind: KubeArmorPolicy
metadata:
  name: block-etc-nginx-write
  namespace: default
spec:
  selector:
    matchLabels:
      app: kubearmor-demo
  file:
    matchDirectories:
      - dir: /etc/nginx/
        recursive: true
        readOnly: true
  action: Block
```

- [ ] **Step 3: Implement the verifier**

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KUBECONFIG_PATH="${KUBECONFIG_PATH:-$ROOT_DIR/generated/kubeconfig}"
WORK_DIR="${WORK_DIR:-$ROOT_DIR/generated/kubearmor-filesystem}"
mkdir -p "$WORK_DIR"

kubectl --kubeconfig "$KUBECONFIG_PATH" apply -f "$ROOT_DIR/k8s/kubearmor-block-etc-nginx-write.yaml" >/dev/null
kubectl --kubeconfig "$KUBECONFIG_PATH" -n default rollout status deploy/kubearmor-demo --timeout=300s >/dev/null
pod_name="$(kubectl --kubeconfig "$KUBECONFIG_PATH" -n default get pod -l app=kubearmor-demo -o jsonpath='{.items[0].metadata.name}')"

set +e
kubectl --kubeconfig "$KUBECONFIG_PATH" -n default exec "$pod_name" -- sh -lc 'echo "# ka-test" >> /etc/nginx/conf.d/default.conf' \
  >"$WORK_DIR/verify.stdout" 2>"$WORK_DIR/verify.stderr"
rc=$?
set -e

printf 'stdout:\n'
cat "$WORK_DIR/verify.stdout"
printf '\nstderr:\n'
cat "$WORK_DIR/verify.stderr"

if [[ $rc -eq 0 ]]; then
  echo
  echo "[WARN] nginx config write succeeded; KubeArmor filesystem block did not trigger."
else
  echo
  echo "[INFO] nginx config write was blocked."
fi
```

- [ ] **Step 4: Implement the matrix-compatible test runner**

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
KUBECONFIG_PATH="$1"
WORK_DIR="$ROOT_DIR/generated/kubearmor-filesystem-matrix"
mkdir -p "$WORK_DIR"
output="$(WORK_DIR="$WORK_DIR" KUBECONFIG_PATH="$KUBECONFIG_PATH" "$ROOT_DIR/scripts/verify-kubearmor-filesystem.sh")"
status="fail"
summary="KubeArmor filesystem write block did not trigger"
if grep -Eqi 'permission denied|not permitted|blocked|read-only' "$WORK_DIR/verify.stderr"; then
  status="pass"
  summary="KubeArmor blocked write access under /etc/nginx"
fi
jq -n --arg status "$status" --arg summary "$summary" --arg output "$output" '{status:$status,summary:$summary,details:{verifierOutput:$output}}'
```

- [ ] **Step 5: Add the new live test to the matrix catalog**

```json
{
  "id": "kubearmor-filesystem-write-block",
  "title": "KubeArmor blocks filesystem writes with readOnly policy",
  "runner": "scripts/tests/kubearmor-filesystem.sh",
  "appliesTo": ["k3s-kubearmor-runc"],
  "goal": "確認 KubeArmor 在套用 file readOnly policy 後可以阻擋實際寫入"
}
```

- [ ] **Step 6: Run the live verifier against the existing KubeArmor cluster**

Run:

```bash
KUBECONFIG_PATH=generated/stacks/k3s-kubearmor-runc/kubeconfig ./scripts/verify-kubearmor-filesystem.sh
./scripts/tests/kubearmor-filesystem.sh generated/stacks/k3s-kubearmor-runc/kubeconfig k3s-kubearmor-runc
```

Expected: the first command reports the write was blocked, and the second emits JSON with `"status":"pass"` if enforcement works.

- [ ] **Step 7: Commit**

```bash
git add k8s/kubearmor-block-etc-nginx-write.yaml scripts/verify-kubearmor-filesystem.sh scripts/tests/kubearmor-filesystem.sh testing/matrix/catalog.json
git commit -m "feat: validate kubearmor filesystem write blocking"
```

### Task 3: Publish Matrix Data From The Existing Azure Environments

**Files:**
- Modify: `testing/results/latest/comparison-matrix.json`
- Modify: `docs/data/comparison-matrix.json`
- Test: `generated/stacks/k3s-gvisor/kubeconfig`
- Test: `generated/stacks/k3s-openshell-runc/kubeconfig`
- Test: `generated/stacks/k3s-openshell-gvisor/kubeconfig`
- Test: `generated/stacks/k3s-kubearmor-runc/kubeconfig`

- [ ] **Step 1: Write the failing publication probe**

Run:

```bash
PUBLISH_RESULTS=true ./scripts/run-comparison-matrix-tests.sh
```

Expected before Task 1: results contain `kubeconfig missing; install this stack first`. After Task 1, this command should be usable against the live environments.

- [ ] **Step 2: Re-run the shared matrix against the live Azure clusters**

Run:

```bash
PUBLISH_RESULTS=true ./scripts/run-comparison-matrix-tests.sh
```

Expected: the command writes `testing/results/latest/comparison-matrix.json` and updates `docs/data/comparison-matrix.json`.

- [ ] **Step 3: Inspect the KubeArmor-related outcomes**

Run:

```bash
jq '.results["k3s-kubearmor-runc"]' testing/results/latest/comparison-matrix.json
```

Expected: includes `kubearmor-sa-block` and `kubearmor-filesystem-write-block` with their live status and summaries.

- [ ] **Step 4: Commit**

```bash
git add testing/results/latest/comparison-matrix.json docs/data/comparison-matrix.json
git commit -m "docs: publish live comparison matrix results"
```

### Task 4: Tighten The Shared Docs Style Guardrails First

**Files:**
- Modify: `scripts/tests/docs-professional-shell.sh`
- Test: `docs/index.html`
- Test: `docs/comparison-four-stacks.html`
- Test: `docs/installs.html`
- Test: `docs/matrix.html`
- Test: `docs/report.html`
- Test: `docs/lab.html`
- Test: `docs/lab-gvisor.html`
- Test: `docs/lab-kata.html`

- [ ] **Step 1: Write the failing docs-style guardrail**

Run:

```bash
bash scripts/tests/docs-professional-shell.sh
```

Expected: the check should fail once the new root-only visual normalization assertions are added, because `docs/comparison-four-stacks.html` still overrides `page-hero` with bespoke surface utilities.

- [ ] **Step 2: Add root-doc visual normalization assertions**

```bash
root_pages=(
  "docs/index.html"
  "docs/comparison-four-stacks.html"
  "docs/installs.html"
  "docs/matrix.html"
  "docs/report.html"
  "docs/lab.html"
  "docs/lab-gvisor.html"
  "docs/lab-kata.html"
)

for page in "${root_pages[@]}"; do
  if grep -Eq 'class="page-hero [^"]*(bg-white|border|rounded-2xl|shadow-sm)' "$page"; then
    echo "root page still overrides page-hero surface in $page" >&2
    exit 1
  fi
done
```

- [ ] **Step 3: Re-run the guardrail to confirm the new assertion is live**

Run:

```bash
bash scripts/tests/docs-professional-shell.sh
```

Expected: fail on one or more root docs pages until the HTML normalization is complete.

- [ ] **Step 4: Commit**

```bash
git add scripts/tests/docs-professional-shell.sh
git commit -m "test: tighten docs visual normalization guardrails"
```

### Task 5: Normalize Shared CSS And Root Docs Visual Primitives

**Files:**
- Modify: `docs/assets/reference.css`
- Modify: `docs/index.html`
- Modify: `docs/comparison-four-stacks.html`
- Modify: `docs/installs.html`
- Modify: `docs/matrix.html`
- Modify: `docs/report.html`
- Modify: `docs/lab.html`
- Modify: `docs/lab-gvisor.html`
- Modify: `docs/lab-kata.html`

- [ ] **Step 1: Update shared CSS so root pages can use one visual language**

```css
.page-hero,
.page-section {
  border: 1px solid #e2e8f0;
  border-radius: 2rem;
  background: #ffffff;
  box-shadow: 0 1px 2px rgba(15, 23, 42, 0.06);
  margin-bottom: 2rem;
  padding: 2rem;
}

.page-card,
.reference-card,
.page-stat {
  border: 1px solid #e2e8f0;
  border-radius: 1rem;
  background: #f8fafc;
}
```

- [ ] **Step 2: Normalize `docs/comparison-four-stacks.html` away from bespoke hero and card surface utilities**

```html
<section class="page-hero">
  <div class="page-hero-grid">
    ...
  </div>
</section>
```

Replace surface-owning utility stacks such as `bg-white border border-slate-200 rounded-2xl p-8 ...` on `page-hero` / `page-card` containers with the shared classes carrying those visuals.

- [ ] **Step 3: Normalize `docs/report.html`, `docs/installs.html`, and `docs/matrix.html` to the same card, CTA, and section treatments as `docs/index.html`**

```html
<article class="page-card reference-card p-6">
  <h2 class="page-card-title">...</h2>
  <p class="page-card-copy">...</p>
</article>
```

Keep each page's current structure, but remove visual drift caused by mixed inline utility stacks.

- [ ] **Step 4: Normalize `docs/lab.html`, `docs/lab-gvisor.html`, and `docs/lab-kata.html` to the same hero, stat, section, and evidence-card surfaces**

```html
<section class="page-section">
  <div class="page-section-header">
    <div class="page-section-kicker">PRIMARY SOURCES</div>
    <h2 class="page-section-title">...</h2>
  </div>
  <div class="page-grid page-grid-2">
    ...
  </div>
</section>
```

- [ ] **Step 5: Re-run the docs shell regression**

Run:

```bash
bash scripts/tests/docs-professional-shell.sh
```

Expected: pass after all root docs pages rely on the shared surfaces instead of bespoke hero overrides.

- [ ] **Step 6: Commit**

```bash
git add docs/assets/reference.css docs/index.html docs/comparison-four-stacks.html docs/installs.html docs/matrix.html docs/report.html docs/lab.html docs/lab-gvisor.html docs/lab-kata.html
git commit -m "docs: normalize root docs visual styling"
```

### Task 6: Update Capability Claims To Match Live Configured Results

**Files:**
- Modify: `docs/comparison-four-stacks.html`
- Modify: `docs/matrix.html`
- Modify: `docs/report.html`
- Modify: `docs/lab-gvisor.html`

- [ ] **Step 1: Find the current unfair or stale capability language**

Run:

```bash
rg -n 'Baseline（無 policy）|unsupported|Filesystem 隔離|KubeArmor file block|KubeArmor process block|KubeArmor network block' docs/comparison-four-stacks.html docs/report.html docs/matrix.html docs/lab-gvisor.html
```

Expected: the grep highlights the places that still describe filesystem support without the configured-capability standard.

- [ ] **Step 2: Update the comparison copy to the configured-capability standard**

```html
<td><span class="status-pill bg-blue-100 text-blue-700">Verified（policy applied, live Azure rerun）</span></td>
```

Use the live matrix results to decide among:

- `not evaluated with policy`
- `verified`
- `degraded`
- `unsupported after policy`

Do not use wording that conflates "default state" with "configured and still unsupported."

- [ ] **Step 3: Update any gVisor/KubeArmor narrative paragraphs that relied on the old framing**

```html
<p class="mt-2 text-sm text-slate-600 dark:text-slate-400">
  This comparison treats a capability as unsupported only after the documented control is enabled and still fails the target scenario.
</p>
```

- [ ] **Step 4: Run the copy sanity check**

Run:

```bash
rg -n 'unsupported by default|無 policy.*不支援|預設不支援' docs/*.html
```

Expected: no matches in root docs pages.

- [ ] **Step 5: Commit**

```bash
git add docs/comparison-four-stacks.html docs/matrix.html docs/report.html docs/lab-gvisor.html
git commit -m "docs: align capability claims with live configured results"
```

### Task 7: Final Verification And Delivery

**Files:**
- Modify: none
- Test: `scripts/tests/docs-professional-shell.sh`
- Test: `scripts/tests/kubearmor-filesystem.sh`
- Test: `scripts/run-comparison-matrix-tests.sh`

- [ ] **Step 1: Re-run the live KubeArmor filesystem test**

Run:

```bash
./scripts/tests/kubearmor-filesystem.sh generated/stacks/k3s-kubearmor-runc/kubeconfig k3s-kubearmor-runc
```

Expected: JSON with a final live status for the configured filesystem-write-block scenario.

- [ ] **Step 2: Re-run the shared matrix publication command one final time**

Run:

```bash
PUBLISH_RESULTS=true ./scripts/run-comparison-matrix-tests.sh
```

Expected: fresh `testing/results/latest/comparison-matrix.json` and `docs/data/comparison-matrix.json`.

- [ ] **Step 3: Re-run the docs regression and diff sanity checks**

Run:

```bash
bash scripts/tests/docs-professional-shell.sh
git diff --check
git status --short
```

Expected:

```text
docs professional shell check passed
```

and a clean worktree after the final commit.

- [ ] **Step 4: Final commit**

```bash
git add docs/assets/reference.css docs/*.html docs/data/comparison-matrix.json testing/results/latest/comparison-matrix.json scripts/tests/docs-professional-shell.sh scripts/tests/kubearmor-filesystem.sh scripts/verify-kubearmor-filesystem.sh scripts/fetch-live-stack-kubeconfigs.sh scripts/lib-stack.sh testing/matrix/catalog.json k8s/kubearmor-block-etc-nginx-write.yaml
git commit -m "docs: normalize styling and revalidate live azure results"
```
