# Professional Technical Reference Visual System & Four Stacks Comparison Document Design

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:writing-plans to create the detailed implementation plan for rolling out this design.

**Goal:** Redesign the entire docs/ site visual language from the current cartoonish/brutalist playful style into a clean, professional, high-information-density engineering technical reference style. Deliver a flagship "四套架構比較技術參考" (Four Stacks Comparison Technical Reference) as the primary artifact that lets engineers quickly understand architectural differences, perform side-by-side comparisons, and trace experimental steps/evidence for the four environments (k3s-gvisor, k3s-openshell-runc, k3s-openshell-gvisor, k3s-kubearmor-runc).

**Design Direction (Locked):** 
- Clean, modern, trustworthy professional reference aesthetic (inspired by high-quality engineering docs like Cilium, Kubernetes references, internal platform specs).
- Excellent scannability and comparison capabilities.
- Full Light/Dark theme support with easily adjustable background treatments.
- Pure static implementation (no heavy build step required; extractable to custom CSS matching the existing site setup).
- Information-dense but calm: focus on data (tables, evidence, matrices), precise language, minimal ornamentation.

**Visual System (Core Tokens & Principles - from approved preview-professional.html):**

### Typography
- Body: Inter (system-ui fallback), 14-16px base, excellent line-height (1.7+ for prose).
- Headings: Space Grotesk or Inter SemiBold, tight tracking for titles, clear hierarchy (no giant all-caps playful display type).
- Monospace: For code, commands, paths, evidence links (IBM Plex Mono or system mono).
- Avoid: Heavy uppercase everywhere, decorative fonts, excessive boldness for playfulness.

### Color & Backgrounds (Light/Dark - Adjustable)
- **Light mode (default for most users):**
  - Page body: `bg-slate-100` (subtle cool gray for gentle separation) or `bg-white` / `#f8fafc` for ultra-clean variant.
  - Primary content container ("document card"): `bg-white border border-slate-200 rounded-2xl` with very light shadow for focus.
  - Text: Slate-800 / Slate-900 for primary, Slate-500/600 for secondary.
  - Accents: Emerald for Verified/positive, Amber for Degraded, Blue for contrasting routes, Slate for neutral/baseline.
- **Dark mode:**
  - Page body: `bg-slate-950` (deep professional dark).
  - Primary content container: `bg-slate-900 border border-slate-700`.
  - Text: Slate-200 / white for primary, Slate-400 for secondary.
  - Tables and cards use adjusted backgrounds (`slate-900` / `slate-800` hovers) for readability.
- Adjustability: Backgrounds defined via clear CSS custom properties or Tailwind classes in a new `assets/professional.css` (or equivalent). Easy to tweak exact shades (e.g., body gray depth, card border strength) without affecting other components. Theme switcher uses `dark` class on `<html>`, with localStorage + system preference detection.
- Status pills / badges: Small, high-contrast, semantic colors (no heavy rounded "chip" playfulness).
- No warm paper tones, heavy drop shadows (10px+), large 999px pills, or radial gradients from old style.

### Layout & Components
- Max-width content (7xl or ~1280px) with comfortable padding.
- Sticky top nav (minimal, professional links + theme toggle).
- Sticky left TOC for long reference docs (optional but recommended for the comparison page).
- Tables as primary comparison tool: Dark header, clean borders, hover states, status indicators inline. Support for the existing comparison-matrix.json data.
- Cards / panels: Subtle borders, minimal or no heavy shadows. Used for "Quick Facts", architecture overviews, evidence.
- Sections: Numbered (01, 02...) + clear semantic headings. Good vertical rhythm.
- Evidence links: Inline, monospace, to raw/ and dated validation reports.
- Theme toggle: Prominent but not distracting (e.g., Light | Dark segmented control in nav). Persists.
- Hero / intro: Restrained, functional. Eyebrow tags for "TECHNICAL REFERENCE", version, last-updated.
- Footer: Minimal legal / provenance note.

### Existing Site Migration Notes
- Replace or heavily refactor `assets/site.css` with the new professional tokens (or create `assets/professional.css` and update links).
- Existing pages (index.html, matrix.html, lab-*.html, report.html) should adopt the new nav, typography, table styles, and light/dark support.
- The comparison matrix (data + tests) remains the data source; the new reference page elevates it with architecture diagrams, decision guide, and experimental traceability.
- Runbooks and raw evidence stay in place; the reference provides high-level navigation + cross-links.
- HTML structure for the flagship page follows the approved preview structure (quick matrix, architecture models, per-dimension analysis, experimental process, decision guide, limitations).

**Content Structure for the Flagship Document ("四套架構比較技術參考")**

1. **Quick Overview & Comparison Matrix**  
   - One-sentence positioning of the four stacks.  
   - High-signal side-by-side table (dimensions: Process identity, Filesystem, Egress, L7 control, Policy hot-reload, SA token, Kernel boundary, etc.).  
   - Status language consistent with existing matrix (Verified / Degraded / N/A / Baseline).  
   - Key conclusions callout.

2. **Architecture Models**  
   - Shared foundation (Azure + k3s + agent-sandbox).  
   - Per-stack layer diagrams (or clear textual models + placeholders for professional diagrams).  
   - Responsibility matrix (Gateway/Supervisor vs gVisor guest vs KubeArmor LSM vs baseline).

3. **Differences Analysis (by Technical Dimension)**  
   - One section per major dimension (Filesystem, Egress, Binary/L7, etc.).  
   - Behavior table + "What we measured" + direct evidence links (to 2026-06 validation reports and raw logs).  
   - Trade-offs highlighted.

4. **Experimental Process & Reproducibility**  
   - How the four environments were built (comparison-matrix installer).  
   - Test execution & publishing flow (catalog.json → runner → docs/data).  
   - Known workarounds (e.g., privileged patcher) and where to find raw evidence.

5. **Decision Guide**  
   - Scenario-based recommendations ("Choose X when you need Y").  
   - Explicit trade-off summary table.

6. **Limitations & Future Work**  
   - Scope of current validation.  
   - Unverified items, next experiments (Kata follow-up if relevant, but not in core four).

**Appendices / Supporting**
- Glossary of terms (OpenShell vs agent-sandbox vs supervisor, etc.).
- Direct links to runbooks, install scripts, raw evidence directories.
- References to official NVIDIA docs + deviations observed in this lab.

**Diagrams & Visual Evidence**
- Recommend 4 consistent architecture layer diagrams (one per stack) + 1 "enforcement point comparison" diagram.
- Use professional tooling (Excalidraw or similar) exported to SVG/PNG, embedded with alt text and source links.
- Mermaid fallbacks for text-only viewing.
- All diagrams must clearly label control vs data flow, enforcement location, and differences vs shared layers.

**Evidence & Provenance Rules**
- Every significant claim must have "Verified on [date], evidence: [link to report or raw/ dir]".
- Use the existing dated validation reports (sandbox-validation, gvisor-validation, landlock-root-cause, etc.) as primary sources.
- Status must match or explain deviations from `docs/data/comparison-matrix.json`.

**Technical Implementation Notes**
- The approved preview (preview-professional.html) demonstrates the exact desired look & feel using Tailwind CDN for rapid iteration.
- For production site: Extract the visual system into a new pure CSS file (recommended to stay consistent with current static docs approach) or introduce a minimal Tailwind build if future pages grow complex.
- Light/Dark: Class-based on `<html>`, with the JS toggle pattern from the preview (system preference + localStorage).
- Navigation and layout should be reusable across pages.
- Keep existing comparison matrix data pipeline intact.
- New document filename suggestion: `docs/comparison-four-stacks.md` (or `.html` rendered version) as the canonical entry point; update README, index.html, and matrix.html to promote it.
- Accessibility: Good contrast, semantic HTML, keyboard-friendly toggle, table captions where useful.

**Success Criteria**
- An engineer new to the lab can, within 10-15 minutes of reading the flagship document:
  - Explain the four stacks and their key differences.
  - Decide which environment suits a given requirement.
  - Know exactly where to go to reproduce a result or see raw logs.
- The new style feels "serious professional technical reference" (no playful/cartoon elements).
- Light and Dark modes are both comfortable and consistent.
- Existing comparison data and evidence are preserved and better surfaced.

**Out of Scope for Initial Rollout**
- Full migration of every legacy lab HTML page on day one (prioritize the comparison reference + nav/style foundation).
- Adding new content beyond the four stacks (Kata etc. can be noted as explored but de-emphasized per earlier direction).
- Heavy JavaScript or client-side rendering (keep mostly static + minimal theme JS).

**Next Steps (after this design is approved)**
- Use writing-plans skill to produce bite-sized implementation tasks (CSS extraction, new comparison page authoring, style application to existing pages, diagram creation, content population from existing architecture.md / validation reports / matrix.json, testing the light/dark toggle, updating links and entry points).
- Create the actual `docs/comparison-four-stacks.md` (or rendered HTML) and supporting assets.
- Update top-level navigation and landing to feature the new reference.

**References**
- Approved live preview: docs/preview-professional.html (the source of truth for the locked visual direction and content skeleton).
- Existing data: docs/data/comparison-matrix.json + runbooks/comparison-matrix-tests.md.
- Evidence base: testing/ dated validation reports and raw/ directories.
- Old explanatory content: docs/openshell-architecture.md, docs/openshell-vs-sandbox.md, docs/openshell-compatibility.md (to be synthesized into the new reference, reducing duplication).

This design document captures the user-validated direction after multiple rounds of preview iteration and feedback. The visual system and the four-stacks comparison reference are now ready for detailed planning and execution.