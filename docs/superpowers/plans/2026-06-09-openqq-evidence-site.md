# OpenQQ Evidence Site Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a GitHub Pages-compatible static evidence portal in `docs/` that turns the current `testing/` reports into a decision-oriented research website.

**Architecture:** Use static HTML pages with shared CSS and JavaScript assets. Keep site content in small structured data modules derived from the current `testing/` conclusions and load the published matrix JSON when available, with a local fallback structure for the current baseline snapshot.

**Tech Stack:** Static HTML, CSS, vanilla JavaScript, published JSON under `docs/data/`, markdown source reports in `testing/`

---

## File Structure

Create:
- `docs/index.html` for the homepage lab brief
- `docs/matrix.html` for the detailed capability matrix
- `docs/failures.html` for the failure catalog page
- `docs/evidence.html` for the evidence index
- `docs/tracks/openshell.html` for the OpenShell route summary
- `docs/tracks/gvisor.html` for the gVisor route summary
- `docs/tracks/kubearmor.html` for the KubeArmor route summary
- `docs/tracks/istio.html` for the Istio route summary
- `docs/assets/site.css` for the shared visual system
- `docs/assets/site.js` for shared navigation, rendering helpers, and page bootstrapping
- `docs/assets/content.js` for structured site content derived from the current reports
- `docs/data/comparison-matrix.json` for the published matrix source used by the site

Modify:
- none

Verification helpers:
- local static server via `python3 -m http.server`
- HTML inspection via `curl`

### Task 1: Publish the matrix data source

**Files:**
- Create: `docs/data/comparison-matrix.json`

- [ ] **Step 1: Write the failing data check**

Run:

```bash
test -f docs/data/comparison-matrix.json
```

Expected:

```text
exit code 1
```

- [ ] **Step 2: Create the published matrix JSON**

Write this file:

```json
{
  "generatedAt": "2026-06-09T13:07:54Z",
  "baseline": {
    "kubernetes": "v1.31.14+k3s1",
    "containerRuntime": "cri-o://1.31.13",
    "istio": "1.30.1",
    "os": "Ubuntu 22.04"
  },
  "recommendedPath": "OpenShell + runc",
  "tracks": [
    {
      "id": "k3s-gvisor",
      "label": "k3s-gvisor",
      "summary": "Cluster baseline and normal Istio sidecars pass, but bare RuntimeClass gvisor and Istio+gVisor remain failed.",
      "results": {
        "nodesReady": "PASS",
        "baselinePod": "PASS",
        "istioControlPlane": "PASS",
        "istioSidecarSmoke": "PASS",
        "gvisorRuntime": "FAIL",
        "istioGvisorSidecar": "FAIL",
        "openshellControlPlane": "N/A",
        "openshellGuardrails": "N/A",
        "kubearmorSa": "N/A",
        "kubearmorProcess": "N/A",
        "kubearmorFile": "N/A",
        "kubearmorNetwork": "N/A"
      }
    },
    {
      "id": "k3s-openshell-runc",
      "label": "k3s-openshell-runc",
      "summary": "Current most stable path with passing OpenShell control plane and guardrails on the stated baseline.",
      "results": {
        "nodesReady": "PASS",
        "baselinePod": "PASS",
        "istioControlPlane": "PASS",
        "istioSidecarSmoke": "PASS",
        "gvisorRuntime": "N/A",
        "istioGvisorSidecar": "N/A",
        "openshellControlPlane": "PASS",
        "openshellGuardrails": "PASS",
        "kubearmorSa": "N/A",
        "kubearmorProcess": "N/A",
        "kubearmorFile": "N/A",
        "kubearmorNetwork": "N/A"
      }
    },
    {
      "id": "k3s-openshell-gvisor",
      "label": "k3s-openshell-gvisor",
      "summary": "OpenShell control plane and guardrails pass, but bare gVisor runtime and Istio+gVisor remain failed.",
      "results": {
        "nodesReady": "PASS",
        "baselinePod": "PASS",
        "istioControlPlane": "PASS",
        "istioSidecarSmoke": "PASS",
        "gvisorRuntime": "FAIL",
        "istioGvisorSidecar": "FAIL",
        "openshellControlPlane": "PASS",
        "openshellGuardrails": "PASS",
        "kubearmorSa": "N/A",
        "kubearmorProcess": "N/A",
        "kubearmorFile": "N/A",
        "kubearmorNetwork": "N/A"
      }
    },
    {
      "id": "k3s-kubearmor-runc",
      "label": "k3s-kubearmor-runc",
      "summary": "File and service-account controls pass, while process and network enforcement remain failed on this rerun.",
      "results": {
        "nodesReady": "PASS",
        "baselinePod": "PASS",
        "istioControlPlane": "PASS",
        "istioSidecarSmoke": "PASS",
        "gvisorRuntime": "N/A",
        "istioGvisorSidecar": "N/A",
        "openshellControlPlane": "N/A",
        "openshellGuardrails": "N/A",
        "kubearmorSa": "PASS",
        "kubearmorProcess": "FAIL",
        "kubearmorFile": "PASS",
        "kubearmorNetwork": "FAIL"
      }
    }
  ]
}
```

- [ ] **Step 3: Run the data check again**

Run:

```bash
python3 -m json.tool docs/data/comparison-matrix.json >/dev/null
```

Expected:

```text
exit code 0
```

- [ ] **Step 4: Commit**

Run:

```bash
git add docs/data/comparison-matrix.json
git commit -m "docs: publish comparison matrix data"
```

### Task 2: Build shared site assets

**Files:**
- Create: `docs/assets/site.css`
- Create: `docs/assets/content.js`
- Create: `docs/assets/site.js`

- [ ] **Step 1: Write the failing asset check**

Run:

```bash
test -f docs/assets/site.css && test -f docs/assets/content.js && test -f docs/assets/site.js
```

Expected:

```text
exit code 1
```

- [ ] **Step 2: Create the CSS design system**

Include:

```css
:root {
  --bg: #f0f9ff;
  --surface: rgba(255, 255, 255, 0.82);
  --surface-strong: #ffffff;
  --surface-muted: #e0f2fe;
  --line: rgba(12, 74, 110, 0.16);
  --line-strong: rgba(12, 74, 110, 0.28);
  --text: #082f49;
  --text-soft: #24506d;
  --text-muted: #40657e;
  --primary: #0369a1;
  --secondary: #0ea5e9;
  --success: #15803d;
  --success-bg: #dcfce7;
  --danger: #b91c1c;
  --danger-bg: #fee2e2;
  --na: #64748b;
  --na-bg: #e2e8f0;
  --shadow: 0 24px 60px rgba(8, 47, 73, 0.08);
  --radius-lg: 28px;
  --radius-md: 18px;
  --radius-sm: 12px;
  --content-width: 1180px;
}
```

Add shared rules for:
- sticky header
- content grid
- cards
- table styles
- status badges
- evidence lists
- responsive collapse
- `focus-visible`
- `prefers-reduced-motion`

- [ ] **Step 3: Create structured content data**

Include:

```js
window.OPENQQ_CONTENT = {
  summaryCards: [],
  unsupportedClaims: [],
  evidenceGroups: [],
  tracks: [],
  failures: []
};
```

Populate each collection with the approved conclusions and links to:
- `testing/comparison-matrix-live-2026-06-09.md`
- `testing/failure-catalog-2026-06-09.md`
- relevant `testing/*.md`
- `docs/runbooks/gvisor-version-proof.md` if present

- [ ] **Step 4: Create the shared rendering script**

Include functions for:

```js
async function loadMatrixData() {}
function renderSummaryCards(cards) {}
function renderUnsupportedClaims(claims) {}
function renderMatrixTable(target, tracks, options) {}
function renderEvidenceGroups(groups) {}
function renderTrackFacts(track) {}
function renderFailures(failures) {}
function initPage() {}
```

Support:
- loading `docs/data/comparison-matrix.json`
- setting active nav state
- rendering status badges with `PASS`, `FAIL`, `N/A`
- bootstrapping page-specific sections via `data-page`

- [ ] **Step 5: Run a syntax verification**

Run:

```bash
node --check docs/assets/content.js && node --check docs/assets/site.js
```

Expected:

```text
exit code 0
```

- [ ] **Step 6: Commit**

Run:

```bash
git add docs/assets/site.css docs/assets/content.js docs/assets/site.js
git commit -m "docs: add shared evidence site assets"
```

### Task 3: Build the homepage and matrix page

**Files:**
- Create: `docs/index.html`
- Create: `docs/matrix.html`

- [ ] **Step 1: Write the failing page check**

Run:

```bash
test -f docs/index.html && test -f docs/matrix.html
```

Expected:

```text
exit code 1
```

- [ ] **Step 2: Create the homepage**

Include:

```html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>OpenQQ Evidence Site</title>
  </head>
  <body data-page="home">
    <header class="site-header"></header>
    <main>
      <section id="research-header"></section>
      <section id="current-assessment"></section>
      <section id="matrix-snapshot"></section>
      <section id="key-limits"></section>
      <section id="evidence-index"></section>
    </main>
    <script src="assets/content.js"></script>
    <script src="assets/site.js"></script>
  </body>
</html>
```

Add:
- metadata cards for baseline
- summary card container
- matrix snapshot container
- unsupported claims list
- evidence group container

- [ ] **Step 3: Create the matrix page**

Include:

```html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Matrix | OpenQQ Evidence Site</title>
  </head>
  <body data-page="matrix">
    <header class="site-header"></header>
    <main>
      <section id="matrix-overview"></section>
      <section id="matrix-table"></section>
    </main>
    <script src="assets/content.js"></script>
    <script src="assets/site.js"></script>
  </body>
</html>
```

Add:
- page intro
- full matrix container
- interpretation notes

- [ ] **Step 4: Run a static HTML smoke check**

Run:

```bash
python3 -m http.server 4173 --directory docs >/tmp/openqq-site.log 2>&1 &
SERVER_PID=$!
sleep 1
curl -I http://127.0.0.1:4173/index.html
curl -I http://127.0.0.1:4173/matrix.html
kill $SERVER_PID
wait $SERVER_PID 2>/dev/null || true
```

Expected:

```text
HTTP/1.0 200 OK
```

- [ ] **Step 5: Commit**

Run:

```bash
git add docs/index.html docs/matrix.html
git commit -m "docs: add homepage and matrix pages"
```

### Task 4: Build track, failure, and evidence pages

**Files:**
- Create: `docs/failures.html`
- Create: `docs/evidence.html`
- Create: `docs/tracks/openshell.html`
- Create: `docs/tracks/gvisor.html`
- Create: `docs/tracks/kubearmor.html`
- Create: `docs/tracks/istio.html`

- [ ] **Step 1: Write the failing page check**

Run:

```bash
test -f docs/failures.html && test -f docs/evidence.html && test -f docs/tracks/openshell.html && test -f docs/tracks/gvisor.html && test -f docs/tracks/kubearmor.html && test -f docs/tracks/istio.html
```

Expected:

```text
exit code 1
```

- [ ] **Step 2: Create the shared page shell**

Each page should follow:

```html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
  </head>
  <body data-page="REPLACE_ME">
    <header class="site-header"></header>
    <main>
      <section class="page-hero"></section>
      <section class="page-body"></section>
    </main>
    <script src="../assets/content.js"></script>
    <script src="../assets/site.js"></script>
  </body>
</html>
```

Use `../assets/*` only for pages under `docs/tracks/`.

- [ ] **Step 3: Add page-specific containers**

Add to:
- `docs/failures.html`: failure summary grid, detailed failure list
- `docs/evidence.html`: grouped evidence index, raw artifact callout, source notes
- track pages: proven items, unsupported items, linked reports, route interpretation

- [ ] **Step 4: Run static route checks**

Run:

```bash
python3 -m http.server 4173 --directory docs >/tmp/openqq-site.log 2>&1 &
SERVER_PID=$!
sleep 1
curl -I http://127.0.0.1:4173/failures.html
curl -I http://127.0.0.1:4173/evidence.html
curl -I http://127.0.0.1:4173/tracks/openshell.html
curl -I http://127.0.0.1:4173/tracks/gvisor.html
curl -I http://127.0.0.1:4173/tracks/kubearmor.html
curl -I http://127.0.0.1:4173/tracks/istio.html
kill $SERVER_PID
wait $SERVER_PID 2>/dev/null || true
```

Expected:

```text
HTTP/1.0 200 OK
```

- [ ] **Step 5: Commit**

Run:

```bash
git add docs/failures.html docs/evidence.html docs/tracks/openshell.html docs/tracks/gvisor.html docs/tracks/kubearmor.html docs/tracks/istio.html
git commit -m "docs: add evidence detail pages"
```

### Task 5: Final verification and polish

**Files:**
- Verify: `docs/index.html`
- Verify: `docs/matrix.html`
- Verify: `docs/failures.html`
- Verify: `docs/evidence.html`
- Verify: `docs/tracks/*.html`
- Verify: `docs/assets/site.css`
- Verify: `docs/assets/content.js`
- Verify: `docs/assets/site.js`
- Verify: `docs/data/comparison-matrix.json`

- [ ] **Step 1: Run the full static verification**

Run:

```bash
python3 -m http.server 4173 --directory docs >/tmp/openqq-site.log 2>&1 &
SERVER_PID=$!
sleep 1
curl -s http://127.0.0.1:4173/index.html >/tmp/openqq-index.html
curl -s http://127.0.0.1:4173/matrix.html >/tmp/openqq-matrix.html
curl -s http://127.0.0.1:4173/failures.html >/tmp/openqq-failures.html
curl -s http://127.0.0.1:4173/evidence.html >/tmp/openqq-evidence.html
test -s /tmp/openqq-index.html
test -s /tmp/openqq-matrix.html
test -s /tmp/openqq-failures.html
test -s /tmp/openqq-evidence.html
kill $SERVER_PID
wait $SERVER_PID 2>/dev/null || true
```

Expected:

```text
exit code 0
```

- [ ] **Step 2: Verify script syntax and JSON integrity**

Run:

```bash
node --check docs/assets/content.js
node --check docs/assets/site.js
python3 -m json.tool docs/data/comparison-matrix.json >/dev/null
```

Expected:

```text
exit code 0
```

- [ ] **Step 3: Review the final diff**

Run:

```bash
git status --short
git diff -- docs
```

Expected:

```text
only the intended site files under docs are changed
```

- [ ] **Step 4: Commit**

Run:

```bash
git add docs
git commit -m "docs: build OpenQQ evidence site"
```

## Self-Review

Spec coverage:
- Homepage research summary is covered in Task 3
- Matrix page is covered in Task 3
- Track pages, failure page, and evidence page are covered in Task 4
- Shared visual system and content rules are covered in Task 2
- Published matrix data path is covered in Task 1
- Verification and GitHub Pages-friendly routing checks are covered in Task 5

Placeholder scan:
- No `TODO`, `TBD`, or deferred implementation phrases remain

Type consistency:
- Shared data source is `window.OPENQQ_CONTENT`
- Shared script entry points are `loadMatrixData`, `renderMatrixTable`, `renderFailures`, `renderEvidenceGroups`, `renderTrackFacts`, and `initPage`
