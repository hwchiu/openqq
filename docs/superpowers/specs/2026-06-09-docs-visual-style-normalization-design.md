# Docs Visual Style Normalization Design

## Context

The root docs pages under `docs/*.html` already share the same navigation shell, theme toggle, and base stylesheet, but they do not all visually match `docs/index.html`.

The mismatch is not primarily about content or routing. It comes from inconsistent use of the shared visual primitives:

- some pages override hero surfaces with bespoke border, radius, shadow, and background utilities
- some cards use different background stacks than the index page
- some sections use different spacing and nested surface treatments
- some dynamic matrix cards still use custom combinations rather than the same card styling language as the index page

The user clarified that the requirement is visual normalization only. Page-specific structure and content should stay intact.

## Goal

Make every root docs page in `docs/*.html` visually follow `docs/index.html` while preserving each page's existing structure, content grouping, and purpose.

## Non-Goals

- Do not rewrite page information architecture to mirror `docs/index.html`
- Do not change the markdown-backed runbook pages under `docs/runbooks/*.html`
- Do not change published content, copy, or evidence links unless needed for visual consistency
- Do not introduce a new design system; `docs/index.html` is the canonical style source

## Selected Approach

Use targeted class normalization.

This keeps each page's current layout logic, but rewrites the page-level HTML and shared CSS so all root docs pages use the same visual primitives as `docs/index.html`:

- `page-hero` as the canonical hero surface
- `page-section` as the canonical section surface
- `page-card` / `reference-card` / `page-stat` as the canonical card surfaces
- shared `page-kicker`, `page-title`, `page-lead`, `page-section-title`, and `page-section-lead`
- the same button and table container treatments that already appear on `docs/index.html`

## Canonical Visual Rules

The following rules define "matching `docs/index.html`'s style":

### Surface hierarchy

- `page-hero` and `page-section` own the major white-surface containers with the same radius, border, shadow, and dark-mode behavior as `docs/index.html`
- pages should not restyle those sections inline with extra utility stacks that materially change their appearance
- nested emphasis blocks may still exist, but they should look like index-style cards rather than bespoke panels

### Card treatment

- feature cards use the same light `bg-white` content-card look as `docs/index.html`
- supporting cards and stat blocks use the same muted `bg-slate-50` / `dark:bg-slate-950` treatment as `docs/index.html`
- card radius, border color, shadow, and hover behavior should come from the shared classes rather than one-off combinations

### Typography and spacing

- heroes use the same display title scale, kicker styling, and lead spacing as `docs/index.html`
- section headings use the same kicker, title, and lead hierarchy
- major sections should retain the same outer spacing rhythm as the index page

### Interactive elements

- primary and secondary CTA buttons should use the same visual treatments already used on `docs/index.html`
- evidence links presented as cards should use the same card styling language as the index page

### Data presentation

- table containers should visually sit inside the same section surfaces and use the existing `tech-table` styling without bespoke wrapper styling
- dynamically rendered matrix stack cards and metric cards should visually match index-style cards

## File Scope

The implementation applies to these root pages:

- `docs/index.html`
- `docs/comparison-four-stacks.html`
- `docs/installs.html`
- `docs/matrix.html`
- `docs/report.html`
- `docs/lab.html`
- `docs/lab-gvisor.html`
- `docs/lab-kata.html`

Runbook wrappers under `docs/runbooks/*.html` remain out of scope for this normalization pass because the user requested `docs/*.html`.

## Page-by-Page Plan

### `docs/index.html`

Treat as the visual reference.

Only adjust it if needed to support a shared class pattern that the other pages can adopt without changing the page's current appearance.

### `docs/comparison-four-stacks.html`

Normalize the hero and stats area so it uses the same surface and stat presentation language as the index page.

Remove bespoke page-level surface utility combinations where `page-hero`, `page-section`, and `page-card` should be carrying the visual treatment already.

### `docs/installs.html`

Keep the current install-path structure, but make the hero, quick-start card, stat cards, install path cards, and guidance sections visually consistent with the index page.

This page already uses most of the right primitives, so changes should focus on removing visual drift rather than restructuring content.

### `docs/matrix.html`

Keep the current data-driven composition, but normalize the hero block, status card, dynamic metric cards, dynamic stack cards, and evidence cards so they look like the index page's cards and sections.

The JavaScript-rendered cards must use the same shared surface and spacing language as static cards.

### `docs/report.html`

Align the hero, recommendation cards, matrix section, and "pages to open next" cards to the same surface hierarchy and spacing as the index page.

### `docs/lab.html`, `docs/lab-gvisor.html`, `docs/lab-kata.html`

Preserve each lab page's content structure while normalizing:

- hero surface treatment
- stat card appearance
- result/evidence card appearance
- section wrappers and nested emphasis panels
- terminal blocks and evidence-card presentation

## Shared CSS Changes

`docs/assets/reference.css` is the only stylesheet that should own the normalized appearance.

Expected CSS work:

- tighten shared surface rules so root docs pages can rely on shared classes without layering bespoke visual overrides
- add any missing shared utility classes only if they represent reusable index-style primitives
- avoid page-specific selectors tied to individual HTML files

## Verification Plan

Verification must prove that the pages now use one visual system rather than a partially shared shell.

### Automated checks

Update `scripts/tests/docs-professional-shell.sh` so it still checks the shared shell, and also checks for the specific visual-normalization guardrails needed for root `docs/*.html` pages.

The test should focus on conditions that reflect the user requirement, for example:

- required shared primitives are present on every root docs page
- no root docs page uses the legacy `assets/site.css`
- no root docs page uses inline `<style>`
- no root docs page overrides the hero and section surfaces with old bespoke page-level shell styling

### Manual sanity check

Inspect diffs for all root `docs/*.html` pages and confirm the work stayed within visual normalization:

- no content deletions
- no navigation regressions
- no runbook routing regressions
- no structural rewrites that collapse page-specific sections into the index page layout

## Risks and Mitigations

### Risk: over-normalizing page structure

Mitigation: keep each page's current sections and only change class usage and shared visual wrappers.

### Risk: styling drift remains in JavaScript-rendered matrix content

Mitigation: treat the matrix page's render functions as part of the visual normalization scope.

### Risk: CSS changes accidentally restyle runbook wrappers

Mitigation: keep new CSS generic and verify the runbook shell check still passes after the root-page changes.

## Success Criteria

The work is complete when:

- the root `docs/*.html` pages all visually read as one system anchored by `docs/index.html`
- per-page layout and content remain intact
- the shared docs regression check passes
- the worktree is committed with the normalization changes
