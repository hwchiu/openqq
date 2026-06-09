# OpenQQ Evidence Site Design

Date: 2026-06-09
Status: Draft approved in conversation, pending final user review of written spec

## Goal

Build a professional technical website under `docs/` for GitHub Pages that turns the material in `testing/` into a readable research portal.

The site is not a product marketing page and not a generic documentation shell. It should read like a lab publication for technical decision makers, while still allowing engineers to drill into evidence, raw reports, and supporting artifacts.

## Audience

Primary audience:
- Technical decision makers
- Maintainers evaluating which path is currently viable

Secondary audience:
- Engineers who need to inspect experiment details, failure evidence, and linked source material

## Product Positioning

This site should present the repository as an evidence-backed research portal for comparing runtime, sandbox, and policy-enforcement paths across a defined Kubernetes baseline.

The homepage must answer these questions quickly:
- What was tested?
- On which version baseline?
- Which path is currently the most stable?
- Which claims are supported?
- Which claims are not supported?
- Where can I verify the evidence?

## Content Reality From Existing Materials

The current `testing/` material is organized around:
- Version baselines
- Capability comparisons
- Current recommended path
- Failure cataloging
- Links to raw artifacts

The strongest recurring narrative in the source material is:
- `OpenShell + runc` is the most stable primary path
- Bare `RuntimeClass gvisor` remains unproven on the stated baseline
- `Istio` control plane and standard sidecar smoke are broadly working
- `OpenShell + gVisor` has narrower success than earlier summaries implied
- `KubeArmor` shows partial enforcement, not blanket runtime protection

The site should preserve that nuance and avoid overclaiming.

## Site Strategy

Recommended pattern:
- Report portal

Tone:
- Research report
- Neutral, rigorous, explicit about scope and limitations

Design direction:
- Minimalism and Swiss-style layout
- High readability
- Strong grid system
- Sparse accent color usage
- Light theme by default

## Information Architecture

The site should have five top-level destinations:

1. `Home`
Contains the executive research summary:
- scope
- version baseline
- current assessment
- key capability snapshot
- key failures and limits
- evidence entry points

2. `Matrix`
Presents the comparison matrix in a cleaner, decision-oriented form:
- environments
- capability columns
- pass/fail/na indicators
- short interpretation notes

3. `Tracks`
Contains dedicated route pages for:
- OpenShell
- gVisor
- KubeArmor
- Istio

Each track page should summarize:
- what is proven
- what is not proven
- known constraints
- linked source reports

4. `Failures`
Presents the failure catalog as a first-class page:
- failure summary cards
- direct evidence excerpts
- interpretation
- link back to matrix and related track

5. `Evidence`
Indexes the supporting reports and raw evidence:
- testing reports
- runbooks under `docs/runbooks/`
- published data files
- raw artifact references when practical

## Homepage Structure

The homepage should behave like an interactive lab brief, not a marketing landing page.

### Section 1: Research Header

Purpose:
- establish scope
- establish credibility
- define the research boundary

Content:
- site title
- one-sentence scope statement
- latest validation date
- Kubernetes version
- container runtime version
- Istio version

Layout:
- restrained split layout
- summary text on the left
- baseline metadata cards on the right

### Section 2: Current Assessment

Purpose:
- provide the fastest possible high-confidence conclusions

Content:
- 3 to 4 summary cards

Expected card themes:
- current recommended path
- gVisor status
- Istio compatibility status
- KubeArmor current enforcement boundary

Each card should have:
- one short title
- one blunt conclusion
- one link to supporting page

### Section 3: Capability Matrix Snapshot

Purpose:
- let readers compare environments immediately without opening a full matrix page

Content:
- a shortened comparison table
- only the highest-signal capability columns on the homepage

Interaction:
- each row or related control should link to the full matrix or corresponding track

### Section 4: Key Failures And Limits

Purpose:
- make negative findings explicit
- prevent the homepage from sounding promotional

Content:
- a concise list of unsupported or disproven claims
- direct links into the failure catalog

Examples of claim framing:
- bare `gvisor` runtime success cannot currently be claimed
- `Istio + RuntimeClass gvisor` cannot currently be claimed ready
- `KubeArmor` cannot currently be described as complete runtime guardrails

### Section 5: Evidence Index

Purpose:
- preserve verifiability
- provide a clear drill-down path for engineers

Content:
- categorized report links
- matrix and rerun reports
- failure catalog
- track-specific reports
- runbooks and implementation notes where relevant

## Navigation

Navigation should remain compact and non-promotional.

Top navigation items:
- Home
- Matrix
- Tracks
- Failures
- Evidence

Behavior:
- sticky header with explicit z-index
- visible active state
- anchor shortcuts on long pages if needed

Footer content:
- repository scope note
- last updated marker
- link to repository root

## Visual System

### Style

Primary visual language:
- clean research interface
- geometric but restrained typography
- strong spacing rhythm
- minimal decoration

Avoid:
- glossy SaaS visuals
- oversized marketing CTAs
- heavy gradients
- dark-mode-first styling
- decorative illustration clutter

### Color

Use a cold technical palette with minimal accents.

Core palette:
- primary: `#0369A1`
- secondary: `#0EA5E9`
- accent/success: `#22C55E`
- background: `#F0F9FF`
- primary text: `#0C4A6E`
- neutral dark text should be introduced where needed for body readability

Semantic status colors should clearly distinguish:
- PASS
- FAIL
- N/A

Status colors must remain readable in table cells and badges.

### Typography

Recommended pairing:
- headings: `Exo`
- body and data-heavy text: `Roboto Mono`

Usage guidance:
- headings should feel technical but controlled
- large narrative blocks must remain readable
- tables, code labels, and metadata should benefit from monospaced treatment

### Motion

Motion should be minimal and purposeful:
- small fade/slide on load
- subtle hover transitions
- no scale-based hover that shifts layout

Accessibility requirement:
- respect `prefers-reduced-motion`

## Content Rules

The site must consistently follow these editorial rules:

- Do not claim success where the source material says partial or failed
- Put version baseline near conclusions, not buried in a footer
- Separate supported conclusions from interpretation
- Preserve links back to source markdown or published JSON where practical
- Favor plain language over vendor or research jargon inflation

## Data And Content Sourcing

Initial implementation can be content-driven and largely static, using the existing markdown and published JSON outputs as source material.

The published data flow already implied by the repository is:
- local runner writes latest results into `testing/results/latest/`
- publish flow updates `docs/data/comparison-matrix.json`

The site should use `docs/data/comparison-matrix.json` as the publishable matrix source where possible, because that matches the existing GitHub Pages publication path.

Supporting content should be derived from:
- `testing/comparison-matrix-live-2026-06-09.md`
- `testing/failure-catalog-2026-06-09.md`
- related validation reports in `testing/`
- relevant runbooks already present under `docs/`

## Implementation Shape

The site should be GitHub Pages friendly with low operational complexity.

Preferred implementation shape:
- static HTML/CSS/JavaScript under `docs/`

Rationale:
- no sign of an existing docs framework in the repository
- easiest deployment path for GitHub Pages
- straightforward linking to local markdown-derived content and published JSON

Expected implementation assets:
- `docs/index.html`
- `docs/matrix.html`
- `docs/tracks/*.html`
- `docs/failures.html`
- `docs/evidence.html`
- `docs/assets/*`
- `docs/data/comparison-matrix.json` consumed as published data

## Accessibility Requirements

The site must meet a professional baseline:

- keyboard-accessible navigation
- visible `focus-visible` states
- semantic landmarks
- sufficient text contrast
- reduced motion support
- responsive behavior at 375px, 768px, 1024px, and 1440px
- no horizontal scroll on mobile

## Testing Expectations

Before considering implementation complete, verify:
- pages render correctly as static files
- navigation works without a framework router
- table layout remains readable on mobile and desktop
- links to evidence pages and local assets resolve correctly from GitHub Pages paths
- published matrix JSON loads without runtime errors

## Risks And Constraints

Primary risks:
- homepage becoming too long or too dense
- matrix readability collapsing on small screens
- accidental overstatement of inconclusive findings
- broken relative links when moved into GitHub Pages structure

Mitigations:
- keep homepage matrix as a snapshot, not the full table
- keep failure content summarized on the homepage and expanded on its own page
- centralize baseline and claim language
- test relative linking from within `docs/`

## Out Of Scope

Not part of this first pass:
- full-text search
- automatic markdown-to-HTML site generation pipeline
- complex client-side filtering UI
- blog or changelog system
- dark theme as a primary design goal

## Success Criteria

The site is successful if:
- a technical decision maker can understand the current recommended path within 3 minutes
- an engineer can reach supporting evidence within 2 clicks from the homepage
- the homepage communicates both strengths and limitations without marketing language
- the site can be served directly from GitHub Pages without extra infrastructure
