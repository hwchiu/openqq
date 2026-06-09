# Decision Lab Pages And Agent Instructions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rework the repository outputs around a current-analysis GitHub Pages site for the K8s Sandbox Decision Lab and add portable repo instructions for Codex and Claude.

**Architecture:** Keep `docs/` as a static site but replace the older evidence-site assumptions with a decision-lab current-state model that is recommendation-first, baseline-aware, and safe to update continuously. Add repo-root instruction files so another machine can reproduce the same working logic without relying on conversation history.

**Tech Stack:** Static HTML/CSS/JavaScript, JSON data files under `docs/data/`, repo-root `AGENTS.md`, repo-root `CLAUDE.md`

---

## File Structure

Create:
- `AGENTS.md` for Codex-oriented repo workflow rules
- `CLAUDE.md` for Claude-compatible wrapper rules
- `docs/data/current-state.json` for recommendation-first Pages data

Modify:
- `README.md` to reflect the Decision Lab purpose and Pages role
- `docs/index.html`
- `docs/matrix.html`
- `docs/failures.html`
- `docs/evidence.html`
- `docs/tracks/openshell.html`
- `docs/tracks/gvisor.html`
- `docs/tracks/kubearmor.html`
- `docs/tracks/istio.html`
- `docs/assets/content.js`
- `docs/assets/site.js`
- `docs/assets/site.css`

Verification:
- `node --check docs/assets/content.js docs/assets/site.js`
- `python3 -m json.tool docs/data/current-state.json`
- local `python3 -m http.server`
- Playwright `webkit` render check against `docs/index.html` and one drill-down page

### Task 1: Define the current-analysis data model

**Files:**
- Create: `docs/data/current-state.json`
- Modify: `docs/assets/content.js`

- [ ] **Step 1: Write the failing data checks**

Run:

```bash
test -f docs/data/current-state.json
```

Expected:

```text
exit code 1
```

- [ ] **Step 2: Create the current-state JSON**

Include fields for:
- recommendation summary
- two baselines
- five candidate solutions
- scenario families
- latest known statuses
- blocked-by-solution-failure state
- evidence pointer placeholders that can later target raw archive locations

- [ ] **Step 3: Rewrite `docs/assets/content.js` around Decision Lab content**

Replace the old 2026-06-09 evidence-site narrative with:
- Chinese site title and summaries
- recommendation-first homepage copy
- solution-centric and scenario-centric navigation labels
- no references to deleted `testing/` markdown files as the primary reading path

- [ ] **Step 4: Verify syntax and JSON integrity**

Run:

```bash
python3 -m json.tool docs/data/current-state.json >/dev/null
node --check docs/assets/content.js
```

Expected:

```text
exit code 0
```

### Task 2: Rework the shared site runtime and styling

**Files:**
- Modify: `docs/assets/site.js`
- Modify: `docs/assets/site.css`

- [ ] **Step 1: Write the failing runtime check**

Run:

```bash
rg -n "OpenQQ Evidence Site|Research Portal|Failure Catalog" docs/assets/site.js docs/assets/site.css
```

Expected:

```text
finds old evidence-site wording and styling assumptions
```

- [ ] **Step 2: Rewrite the site runtime**

Update `docs/assets/site.js` so the site can render:
- current recommendation homepage
- baseline overview
- solution drill-down pages
- scenario drill-down summaries
- methodology / evidence page

Use `docs/data/current-state.json` as the main runtime data source.

- [ ] **Step 3: Rewrite the shared styling**

Update `docs/assets/site.css` to a darker, denser technical reading style:
- Chinese-first content spacing
- low-animation interface
- console-like tables
- restrained dark palette
- strong PASS / FAIL / BLOCKED / NOT TESTED semantics

- [ ] **Step 4: Verify script syntax**

Run:

```bash
node --check docs/assets/site.js
```

Expected:

```text
exit code 0
```

### Task 3: Rebuild the Pages structure around current analysis

**Files:**
- Modify: `docs/index.html`
- Modify: `docs/matrix.html`
- Modify: `docs/failures.html`
- Modify: `docs/evidence.html`
- Modify: `docs/tracks/openshell.html`
- Modify: `docs/tracks/gvisor.html`
- Modify: `docs/tracks/kubearmor.html`
- Modify: `docs/tracks/istio.html`

- [ ] **Step 1: Write the failing content check**

Run:

```bash
rg -n "OpenQQ Evidence Site|Comparison matrix|Failures|Evidence" docs/index.html docs/matrix.html docs/failures.html docs/evidence.html docs/tracks/*.html
```

Expected:

```text
finds legacy English shells and page assumptions
```

- [ ] **Step 2: Rewrite the homepage**

Make `docs/index.html` a recommendation-first Chinese homepage with:
- current recommendation
- two baseline state summary
- blocked candidates summary
- key scenario outcomes
- links to solution, baseline, and scenario drill-downs

- [ ] **Step 3: Rewrite the drill-down pages**

Make the remaining pages serve these roles:
- `docs/matrix.html`: baseline + candidate matrix
- `docs/failures.html`: scenario/risk-oriented blocked and failed states
- `docs/evidence.html`: methodology, data model, raw archive policy
- `docs/tracks/*.html`: solution-oriented current analysis pages

- [ ] **Step 4: Run static route checks**

Run:

```bash
python3 -m http.server 4178 --directory docs >/tmp/openqq-pages.log 2>&1 &
SERVER_PID=$!
sleep 1
python3 - <<'PY'
from urllib.request import urlopen
for path in [
    'index.html', 'matrix.html', 'failures.html', 'evidence.html',
    'tracks/openshell.html', 'tracks/gvisor.html', 'tracks/kubearmor.html', 'tracks/istio.html',
    'assets/site.css', 'assets/site.js', 'assets/content.js',
    'data/comparison-matrix.json', 'data/current-state.json'
]:
    with urlopen(f'http://127.0.0.1:4178/{path}') as resp:
        assert resp.status == 200, (path, resp.status)
print('ok')
PY
STATUS=$?
kill $SERVER_PID
wait $SERVER_PID 2>/dev/null || true
exit $STATUS
```

Expected:

```text
ok
```

### Task 4: Add portable agent instructions

**Files:**
- Create: `AGENTS.md`
- Create: `CLAUDE.md`
- Modify: `README.md`

- [ ] **Step 1: Write the failing instruction check**

Run:

```bash
test -f AGENTS.md || test -f CLAUDE.md
```

Expected:

```text
exit code 1
```

- [ ] **Step 2: Create `AGENTS.md`**

Document:
- repo purpose as a K8s Sandbox Decision Lab
- two fixed baselines
- five candidates
- three decision dimensions
- explicit-guardrail testing rule
- raw archive vs current state vs Pages outputs
- install/bootstrap failure classification rule
- expectation to keep GitHub Pages as the continuously updated official analysis

- [ ] **Step 3: Create `CLAUDE.md`**

Mirror the same operating rules in a Claude-friendly repo instruction file and point back to `AGENTS.md` as the canonical source where useful.

- [ ] **Step 4: Update `README.md`**

Replace the older four-stack framing with:
- Decision Lab framing
- current outputs model
- GitHub Pages role
- where raw archive and current-state data belong

### Task 5: Final verification

**Files:**
- Verify: `AGENTS.md`
- Verify: `CLAUDE.md`
- Verify: `README.md`
- Verify: `docs/assets/site.css`
- Verify: `docs/assets/site.js`
- Verify: `docs/assets/content.js`
- Verify: `docs/data/current-state.json`
- Verify: `docs/*.html`
- Verify: `docs/tracks/*.html`

- [ ] **Step 1: Run syntax and data checks**

Run:

```bash
python3 -m json.tool docs/data/current-state.json >/dev/null
node --check docs/assets/content.js
node --check docs/assets/site.js
```

Expected:

```text
exit code 0
```

- [ ] **Step 2: Run browser rendering verification**

Run:

```bash
python3 -m http.server 4179 --directory docs >/tmp/openqq-pages-browser.log 2>&1 &
SERVER_PID=$!
python3 - <<'PY'
import asyncio
from playwright.async_api import async_playwright

async def main():
    async with async_playwright() as p:
        browser = await p.webkit.launch()
        page = await browser.new_page()
        await page.goto('http://127.0.0.1:4179/index.html', wait_until='networkidle')
        body = await page.text_content('body')
        assert '目前推薦方案' in body
        assert 'Decision Lab' in body
        await page.goto('http://127.0.0.1:4179/tracks/openshell.html', wait_until='networkidle')
        body = await page.text_content('body')
        assert 'OpenShell' in body
        await browser.close()
    print('playwright-ok')

asyncio.run(main())
PY
STATUS=$?
kill $SERVER_PID
wait $SERVER_PID 2>/dev/null || true
exit $STATUS
```

Expected:

```text
playwright-ok
```

- [ ] **Step 3: Review the resulting diff**

Run:

```bash
git status --short
git diff -- README.md AGENTS.md CLAUDE.md docs
```

Expected:

```text
only the intended instruction files and Pages files are changed
```

## Self-Review

Spec coverage:
- Decision Lab framing is covered by Tasks 1, 3, and 4
- current-analysis Pages model is covered by Tasks 1 through 3
- cross-machine workflow instructions are covered by Task 4
- verification and browser rendering checks are covered by Task 5

Placeholder scan:
- no TODO or TBD markers remain

Type consistency:
- the main runtime data source is `docs/data/current-state.json`
- Pages content stays recommendation-first and Chinese-first
