# CRI-O Family Cilium Baseline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Flannel with Cilium for all CRI-O family candidates and reset the official CRI-O comparison baseline to `K3s + CRI-O + Cilium`.

**Architecture:** Remove Flannel-specific wiring from CRI-O cloud-init templates, bootstrap K3s with flannel disabled, then install Cilium through a shared post-bootstrap script before candidate-specific layers such as OpenShell or KubeArmor. Update regression checks and current-state/docs so the repo’s official interpretation matches the new platform baseline.

**Tech Stack:** Terraform, Azure cloud-init templates, K3s, CRI-O, Cilium Helm install, Bash regression tests, GitHub Pages JSON/docs

---

### Task 1: Replace Flannel-specific CRI-O cloud-init wiring

**Files:**
- Modify: `terraform/templates/cloud-init-server.yaml.tftpl`
- Modify: `terraform/templates/cloud-init-agent.yaml.tftpl`
- Test: `scripts/tests/crio-cni-wiring-regression.sh`

- [ ] **Step 1: Write the failing regression expectation**

Update the regression test to stop asserting Flannel pins and instead assert:

```bash
assert_not_contains "$template" '10-flannel.conflist' \
  'CRI-O templates should no longer pin a flannel CNI config'
assert_not_contains "$template" '--flannel-cni-conf' \
  'CRI-O templates should not pass a flannel CNI config flag'
assert_contains "$template" '--flannel-backend=none' \
  'CRI-O templates should disable built-in flannel before Cilium install'
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash scripts/tests/crio-cni-wiring-regression.sh`
Expected: FAIL because templates still reference Flannel.

- [ ] **Step 3: Write minimal template changes**

In both cloud-init templates:

- remove the `write_files` entry for `/etc/rancher/k3s/10-flannel.conflist`
- remove `runtime_args+=(--flannel-cni-conf /etc/rancher/k3s/10-flannel.conflist)`
- append `--flannel-backend=none` to the CRI-O K3s install arguments
- keep CRI-O install and `/etc/cni/net.d` / `/opt/cni/bin` preparation
- keep the `finalize-crio-cni-*` scripts only for binary path setup and CRI-O restart

- [ ] **Step 4: Run regression to verify it passes**

Run: `bash scripts/tests/crio-cni-wiring-regression.sh`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add terraform/templates/cloud-init-server.yaml.tftpl terraform/templates/cloud-init-agent.yaml.tftpl scripts/tests/crio-cni-wiring-regression.sh
git commit -m "feat: switch crio templates to no-flannel bootstrap"
```

### Task 2: Add shared Cilium install/verify flow for CRI-O family

**Files:**
- Create: `scripts/install-cilium-stack.sh`
- Modify: `scripts/lib-stack.sh`
- Test: `scripts/install-cilium-stack.sh`

- [ ] **Step 1: Add shared install script**

Create `scripts/install-cilium-stack.sh` that:

- requires `helm` and `kubectl`
- accepts `KUBECONFIG_PATH`
- installs or upgrades `cilium/cilium`
- waits for `daemonset/cilium` and `deployment/cilium-operator`

Core command shape:

```bash
helm repo add cilium https://helm.cilium.io >/dev/null 2>&1 || true
helm repo update cilium >/dev/null
helm upgrade --install cilium cilium/cilium \
  --kubeconfig "$KUBECONFIG_PATH" \
  --namespace kube-system \
  --wait \
  --timeout 10m \
  --set kubeProxyReplacement=false
kubectl --kubeconfig "$KUBECONFIG_PATH" -n kube-system rollout status ds/cilium --timeout=600s
kubectl --kubeconfig "$KUBECONFIG_PATH" -n kube-system rollout status deploy/cilium-operator --timeout=600s
```

- [ ] **Step 2: Add a small shared helper if needed**

If repeated wait logic is useful, add a focused helper in `scripts/lib-stack.sh` rather than duplicating long loops.

- [ ] **Step 3: Check script syntax**

Run: `bash -n scripts/install-cilium-stack.sh scripts/lib-stack.sh`
Expected: no output

- [ ] **Step 4: Commit**

```bash
git add scripts/install-cilium-stack.sh scripts/lib-stack.sh
git commit -m "feat: add shared cilium install flow"
```

### Task 3: Rewire CRI-O family install scripts to use Cilium first

**Files:**
- Modify: `scripts/install-k3s-crio.sh`
- Modify: `scripts/install-k3s-crio-134.sh`
- Modify: `scripts/install-k3s-openshell-runc-134.sh`
- Modify: `scripts/install-k3s-kubearmor-runc-134.sh`

- [ ] **Step 1: Update plain CRI-O flows**

After `wait_for_nodes_ready`, invoke:

```bash
KUBECONFIG_PATH="$KUBECONFIG_PATH" "$ROOT_DIR/scripts/install-cilium-stack.sh"
```

Then keep the final informational echo.

- [ ] **Step 2: Update OpenShell + CRI-O flow**

Insert the same Cilium install step before:

```bash
KUBECONFIG_PATH="$KUBECONFIG_PATH" "$ROOT_DIR/scripts/install-openshell-stack.sh"
```

- [ ] **Step 3: Update KubeArmor + CRI-O flow**

Insert the same Cilium install step before:

```bash
KUBECONFIG_PATH="$KUBECONFIG_PATH" "$ROOT_DIR/scripts/install-kubearmor-stack.sh"
```

- [ ] **Step 4: Syntax-check all scripts**

Run:

```bash
bash -n scripts/install-k3s-crio.sh \
  scripts/install-k3s-crio-134.sh \
  scripts/install-k3s-openshell-runc-134.sh \
  scripts/install-k3s-kubearmor-runc-134.sh
```

Expected: no output

- [ ] **Step 5: Commit**

```bash
git add scripts/install-k3s-crio.sh scripts/install-k3s-crio-134.sh scripts/install-k3s-openshell-runc-134.sh scripts/install-k3s-kubearmor-runc-134.sh
git commit -m "feat: install cilium before crio-family candidates"
```

### Task 4: Remove Flannel assumptions from gVisor-side helper logic

**Files:**
- Modify: `scripts/install-gvisor-stack.sh`
- Test: `scripts/install-gvisor-stack.sh`

- [ ] **Step 1: Delete Flannel patch logic**

Remove the block that edits:

```bash
FLANNEL_CONFLIST="/var/lib/rancher/k3s/agent/etc/cni/net.d/10-flannel.conflist"
```

because the official CRI-O baseline is no longer Flannel-based.

- [ ] **Step 2: Keep only gVisor-specific runtime wiring**

Retain:

- `runsc` install
- CRI-O runtime drop-ins
- CRI-O restarts
- `RuntimeClass` creation

- [ ] **Step 3: Syntax-check**

Run: `bash -n scripts/install-gvisor-stack.sh`
Expected: no output

- [ ] **Step 4: Commit**

```bash
git add scripts/install-gvisor-stack.sh
git commit -m "refactor: drop flannel patching from gvisor helper"
```

### Task 5: Rewrite regression test around Cilium baseline assumptions

**Files:**
- Modify: `scripts/tests/crio-cni-wiring-regression.sh`

- [ ] **Step 1: Replace Flannel-focused assertions**

Make the test assert all CRI-O templates:

- do not mention `10-flannel.conflist`
- do not mention `--flannel-cni-conf`
- do mention `--flannel-backend=none`

- [ ] **Step 2: Add install-script assertions**

Assert CRI-O family install scripts contain:

```bash
"scripts/install-cilium-stack.sh"
```

for:

- `scripts/install-k3s-crio.sh`
- `scripts/install-k3s-crio-134.sh`
- `scripts/install-k3s-openshell-runc-134.sh`
- `scripts/install-k3s-kubearmor-runc-134.sh`

- [ ] **Step 3: Run the regression test**

Run: `bash scripts/tests/crio-cni-wiring-regression.sh`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add scripts/tests/crio-cni-wiring-regression.sh
git commit -m "test: enforce cilium baseline for crio family"
```

### Task 6: Update decision docs and current-state to formalize the baseline switch

**Files:**
- Modify: `docs/data/current-state.json`
- Create: `docs/reports/2026-06-10-crio-family-cilium-baseline-switch.md`
- Modify: `docs/reports/2026-06-10-k3s-crio-baseline-failure.md`
- Modify: `docs/reports/2026-06-10-k3s-crio-134-baseline-failure.md`
- Modify: `docs/reports/2026-06-10-k3s-openshell-runc-134-bootstrap-blocked.md`
- Modify: `docs/reports/2026-06-10-k3s-gvisor-134-runtime-failure.md`

- [ ] **Step 1: Add a baseline-switch report**

Document that:

- CRI-O family candidates are now formally evaluated on Cilium
- Flannel-based findings are historical and superseded
- new retests must be interpreted on the Cilium baseline

- [ ] **Step 2: Rewrite current-state language**

Update recommendation/overview text so it explicitly states:

- CRI-O family formal baseline has changed to Cilium
- Flannel-derived findings are historical evidence
- recommendation confidence must be re-established after Cilium retests

- [ ] **Step 3: Mark older Flannel reports as historical**

Add a short note near the top of the existing failure reports that they describe the old Flannel-based baseline.

- [ ] **Step 4: Validate JSON**

Run: `python3 -m json.tool docs/data/current-state.json >/dev/null`
Expected: exit 0

- [ ] **Step 5: Commit**

```bash
git add docs/data/current-state.json docs/reports/2026-06-10-crio-family-cilium-baseline-switch.md docs/reports/2026-06-10-k3s-crio-baseline-failure.md docs/reports/2026-06-10-k3s-crio-134-baseline-failure.md docs/reports/2026-06-10-k3s-openshell-runc-134-bootstrap-blocked.md docs/reports/2026-06-10-k3s-gvisor-134-runtime-failure.md
git commit -m "docs: switch crio-family baseline to cilium"
```

### Task 7: Final verification and publish

**Files:**
- Modify: staged files from Tasks 1-6

- [ ] **Step 1: Run final local verification**

Run:

```bash
bash scripts/tests/crio-cni-wiring-regression.sh
python3 -m json.tool docs/data/current-state.json >/dev/null
bash -n scripts/lib-stack.sh scripts/install-cilium-stack.sh scripts/install-k3s-crio.sh scripts/install-k3s-crio-134.sh scripts/install-k3s-openshell-runc-134.sh scripts/install-k3s-kubearmor-runc-134.sh scripts/install-gvisor-stack.sh
git status --short
```

Expected:

- regression test passes
- JSON validation passes
- syntax checks pass
- only intended tracked changes remain

- [ ] **Step 2: Create a single publish commit if the branch is still uncommitted**

```bash
git add docs scripts terraform
git commit -m "feat: move crio-family baseline to cilium"
```

- [ ] **Step 3: Push**

Run: `git push origin main`
Expected: push succeeds
