(function () {
  const CONTENT = window.OPENQQ_CONTENT || {};
  const MATRIX_COLUMNS = [
    ["nodesReady", "Nodes"],
    ["istioControlPlane", "Istio CP"],
    ["istioSidecarSmoke", "Istio Smoke"],
    ["gvisorRuntime", "gVisor"],
    ["istioGvisorSidecar", "Istio+gVisor"],
    ["openshellGuardrails", "OpenShell"],
    ["kubearmorSa", "KA SA"],
    ["kubearmorFile", "KA File"],
    ["kubearmorProcess", "KA Proc"],
    ["kubearmorNetwork", "KA Net"]
  ];

  function getRoot() {
    return document.body.dataset.root || ".";
  }

  function rootPath(path) {
    return `${getRoot()}/${path}`.replace("/./", "/");
  }

  function repoLink(path) {
    return `${CONTENT.repo.blobBase}${path}`;
  }

  function pageLink(path) {
    return rootPath(path);
  }

  async function loadMatrixData() {
    const response = await fetch(rootPath("data/comparison-matrix.json"));
    if (!response.ok) {
      throw new Error(`Failed to load matrix data: ${response.status}`);
    }
    return response.json();
  }

  function statusBadge(value) {
    const lower = String(value || "N/A").toLowerCase();
    const label = lower === "pass" ? "PASS" : lower === "fail" ? "FAIL" : "N/A";
    const className = lower === "pass" ? "status-pass" : lower === "fail" ? "status-fail" : "status-na";
    return `<span class="status ${className}">${label}</span>`;
  }

  function buildHeader() {
    const page = document.body.dataset.page;
    const nav = [
      ["home", pageLink("index.html"), "Home"],
      ["matrix", pageLink("matrix.html"), "Matrix"],
      ["tracks", pageLink("tracks/openshell.html"), "Tracks"],
      ["failures", pageLink("failures.html"), "Failures"],
      ["evidence", pageLink("evidence.html"), "Evidence"]
    ];
    return `
      <div class="site-header-inner">
        <a class="brand" href="${pageLink("index.html")}">
          <span class="brand-kicker">Research Portal</span>
          <span class="brand-title">${CONTENT.header.title}</span>
        </a>
        <nav class="site-nav" aria-label="Primary">
          ${nav
            .map(([id, href, label]) => {
              const active = page === id || (page === "track" && id === "tracks");
              return `<a class="${active ? "active" : ""}" href="${href}">${label}</a>`;
            })
            .join("")}
        </nav>
      </div>
    `;
  }

  function buildFooter(matrix) {
    return `
      <div class="site-footer-inner">
        <div>
          Research scope: runtime, sandbox, and policy-enforcement comparisons on ${matrix.baseline.kubernetes} and ${matrix.baseline.containerRuntime}.
        </div>
        <div>
          Updated ${matrix.generatedAt} · <a class="footnote-link" href="${CONTENT.repo.home}">Repository</a>
        </div>
      </div>
    `;
  }

  function renderSummaryCards(cards) {
    return cards
      .map(
        (card) => `
          <article class="summary-card">
            <div class="section-label">${card.title}</div>
            <div class="verdict">${card.verdict}</div>
            <p>${card.body}</p>
            <a class="summary-link" href="${pageLink(card.href)}">${card.linkLabel}</a>
          </article>
        `
      )
      .join("");
  }

  function renderUnsupportedClaims(claims) {
    return `
      <ul class="claim-list">
        ${claims
          .map(
            (item) => `
              <li>
                <a href="${pageLink(item.href)}">${item.claim}</a>
              </li>
            `
          )
          .join("")}
      </ul>
    `;
  }

  function renderMatrixTable(target, tracks, options) {
    const columns = options.columns;
    target.innerHTML = `
      <div class="matrix-scroll">
        <table>
          <thead>
            <tr>
              <th>Environment</th>
              ${columns.map(([, label]) => `<th>${label}</th>`).join("")}
            </tr>
          </thead>
          <tbody>
            ${tracks
              .map(
                (track) => `
                  <tr>
                    <td class="track-cell">
                      <strong>${track.label}</strong>
                      <span>${track.summary}</span>
                    </td>
                    ${columns.map(([key]) => `<td>${statusBadge(track.results[key])}</td>`).join("")}
                  </tr>
                `
              )
              .join("")}
          </tbody>
        </table>
      </div>
    `;
  }

  function renderEvidenceGroups(groups) {
    return groups
      .map(
        (group) => `
          <article class="evidence-group">
            <div class="section-label">Evidence Group</div>
            <h3>${group.title}</h3>
            <ul class="evidence-list">
              ${group.items
                .map(
                  (item) => `
                    <li>
                      <a href="${repoLink(item.path)}">${item.label}</a>
                      <p>${item.note}</p>
                    </li>
                  `
                )
                .join("")}
            </ul>
          </article>
        `
      )
      .join("");
  }

  function renderTrackFacts(track) {
    return `
      <div class="split">
        <article class="fact-card">
          <div class="section-label">Proven</div>
          <h3>Supported by the current record</h3>
          <ul class="facts-list">
            ${track.proven.map((item) => `<li>${item}</li>`).join("")}
          </ul>
        </article>
        <article class="fact-card">
          <div class="section-label">Not Proven</div>
          <h3>Claims that should be avoided</h3>
          <ul class="facts-list">
            ${track.notProven.map((item) => `<li>${item}</li>`).join("")}
          </ul>
        </article>
      </div>
      <article class="track-summary">
        <div class="section-label">Interpretation</div>
        <p>${track.interpretation}</p>
      </article>
      <article class="page-section">
        <div class="section-label">Related Reports</div>
        <ul class="evidence-list">
          ${track.related
            .map(
              (path) => `
                <li>
                  <a href="${repoLink(path)}">${path}</a>
                </li>
              `
            )
            .join("")}
        </ul>
      </article>
    `;
  }

  function renderFailures(failures) {
    return failures
      .map(
        (failure) => `
          <article class="failure-card" id="${failure.id}">
            <div class="section-label">${failure.verdict}</div>
            <h3>${failure.title}</h3>
            <p>${failure.detail}</p>
            <ul class="failure-list">
              ${failure.evidence
                .map(
                  (path) => `
                    <li>
                      <a href="${repoLink(path)}">${path}</a>
                    </li>
                  `
                )
                .join("")}
            </ul>
          </article>
        `
      )
      .join("");
  }

  function setSectionHeader(id, label, title, description) {
    const target = document.getElementById(id);
    if (!target) {
      return null;
    }
    target.innerHTML = `
      <div class="section-header">
        <div>
          <div class="section-label">${label}</div>
          <h2>${title}</h2>
          <p>${description}</p>
        </div>
      </div>
    `;
    return target;
  }

  function renderHome(matrix) {
    const hero = document.getElementById("research-header");
    hero.innerHTML = `
      <section class="hero">
        <div>
          <div class="eyebrow">Research Header</div>
          <h1>${CONTENT.header.title}</h1>
          <p class="lede">${CONTENT.header.scope}</p>
          <p>
            The current published record compares four environments on the same baseline and separates what is proven from what remains failed or only partially supported.
          </p>
        </div>
        <div class="meta-grid">
          <div class="meta-card"><span class="meta-label">Latest validation</span><span class="meta-value">${matrix.generatedAt}</span></div>
          <div class="meta-card"><span class="meta-label">Kubernetes</span><span class="meta-value">${matrix.baseline.kubernetes}</span></div>
          <div class="meta-card"><span class="meta-label">Container runtime</span><span class="meta-value">${matrix.baseline.containerRuntime}</span></div>
          <div class="meta-card"><span class="meta-label">Istio</span><span class="meta-value">${matrix.baseline.istio}</span></div>
        </div>
      </section>
    `;

    const assessment = setSectionHeader(
      "current-assessment",
      "Current Assessment",
      "Fast conclusions from the current record",
      "This section is optimized for technical decision makers who need the present state before reading the supporting reports."
    );
    assessment.insertAdjacentHTML("beforeend", `<div class="card-grid">${renderSummaryCards(CONTENT.summaryCards)}</div>`);

    const snapshot = setSectionHeader(
      "matrix-snapshot",
      "Capability Snapshot",
      "High-signal matrix view",
      "A compressed comparison of the most decision-relevant capabilities. The full table lives on the Matrix page."
    );
    const matrixCard = document.createElement("article");
    matrixCard.className = "matrix-card";
    snapshot.appendChild(matrixCard);
    renderMatrixTable(matrixCard, matrix.tracks, {
      columns: MATRIX_COLUMNS.filter(([key]) =>
        ["istioSidecarSmoke", "gvisorRuntime", "istioGvisorSidecar", "openshellGuardrails", "kubearmorFile", "kubearmorProcess"].includes(key)
      )
    });
    matrixCard.insertAdjacentHTML(
      "beforeend",
      `<p style="margin-top:14px"><a class="inline-link" href="${pageLink("matrix.html")}">Open full matrix</a></p>`
    );

    const limits = setSectionHeader(
      "key-limits",
      "Key Failures And Limits",
      "Claims the current evidence does not support",
      "Negative findings are first-class content here to keep the site aligned with the underlying reports."
    );
    const limitCard = document.createElement("article");
    limitCard.className = "page-section";
    limitCard.innerHTML = renderUnsupportedClaims(CONTENT.unsupportedClaims);
    limits.appendChild(limitCard);

    const evidence = setSectionHeader(
      "evidence-index",
      "Evidence Index",
      "Direct paths into the source material",
      "Engineers should be able to reach the supporting record in one or two clicks from the homepage."
    );
    evidence.insertAdjacentHTML("beforeend", `<div class="evidence-grid">${renderEvidenceGroups(CONTENT.evidenceGroups)}</div>`);
  }

  function renderMatrixPage(matrix) {
    const overview = document.getElementById("matrix-overview");
    overview.innerHTML = `
      <section class="page-hero">
        <div class="page-title-row">
          <div>
            <div class="eyebrow">Matrix</div>
            <h1>Comparison matrix</h1>
          </div>
          <div class="page-tag">${matrix.recommendedPath}</div>
        </div>
        <p>
          This page keeps the decision-facing matrix readable while preserving the exact pass, fail, and not-applicable boundaries from the 2026-06-09 rerun.
        </p>
      </section>
    `;
    const container = document.getElementById("matrix-table");
    container.innerHTML = `
      <article class="page-section">
        <div class="callout">
          Standard Istio smoke is PASS across all four routes. The active instability boundary is concentrated around gVisor workload readiness and KubeArmor process/network enforcement.
        </div>
      </article>
      <article class="page-section"></article>
    `;
    renderMatrixTable(container.lastElementChild, matrix.tracks, { columns: MATRIX_COLUMNS });
  }

  function renderTrackPage() {
    const slug = document.body.dataset.track;
    const track = CONTENT.tracks.find((item) => item.slug === slug);
    const hero = document.getElementById("track-hero");
    const body = document.getElementById("track-body");
    if (!track) {
      hero.innerHTML = `<section class="page-hero"><h1>Track not found</h1></section>`;
      return;
    }
    hero.innerHTML = `
      <section class="page-hero" id="${slug === "openshell" ? "openshell-gvisor" : ""}">
        <div class="page-title-row">
          <div>
            <div class="eyebrow">${track.heroTag}</div>
            <h1>${track.title}</h1>
          </div>
          <div class="page-tag">${track.subtitle}</div>
        </div>
        <p>${track.interpretation}</p>
      </section>
    `;
    body.innerHTML = renderTrackFacts(track);
  }

  function renderFailuresPage() {
    const hero = document.getElementById("failures-hero");
    const body = document.getElementById("failures-body");
    hero.innerHTML = `
      <section class="page-hero">
        <div class="page-title-row">
          <div>
            <div class="eyebrow">Failure Catalog</div>
            <h1>Explicit failure record</h1>
          </div>
          <div class="page-tag">Do not overclaim</div>
        </div>
        <p>
          This page keeps the failed cases visible and traceable. It is designed to prevent the website from drifting into promotional language.
        </p>
      </section>
    `;
    body.innerHTML = `<div class="failure-grid">${renderFailures(CONTENT.failures)}</div>`;
  }

  function renderEvidencePage() {
    const hero = document.getElementById("evidence-hero");
    const body = document.getElementById("evidence-body");
    hero.innerHTML = `
      <section class="page-hero">
        <div class="page-title-row">
          <div>
            <div class="eyebrow">Evidence</div>
            <h1>Source material and raw artifacts</h1>
          </div>
          <div class="page-tag">GitHub-linked</div>
        </div>
        <p>
          Because GitHub Pages only publishes the content under docs, the links on this page route back to the repository source for markdown reports and raw artifacts.
        </p>
      </section>
    `;
    body.innerHTML = `
      <article class="page-section">
        <div class="callout">
          Published website data comes from <a class="inline-link" href="${repoLink("docs/data/comparison-matrix.json")}">docs/data/comparison-matrix.json</a>. Supporting markdown and raw artifacts stay in the repository and are linked directly from here.
        </div>
      </article>
      <div class="evidence-grid">${renderEvidenceGroups(CONTENT.evidenceGroups)}</div>
    `;
  }

  async function initPage() {
    const page = document.body.dataset.page;
    const matrix = await loadMatrixData();
    const header = document.querySelector(".site-header");
    const footer = document.querySelector(".site-footer");
    header.innerHTML = buildHeader();
    footer.innerHTML = buildFooter(matrix);

    if (page === "home") {
      renderHome(matrix);
    } else if (page === "matrix") {
      renderMatrixPage(matrix);
    } else if (page === "track") {
      renderTrackPage();
    } else if (page === "failures") {
      renderFailuresPage();
    } else if (page === "evidence") {
      renderEvidencePage();
    }
  }

  initPage().catch((error) => {
    const fallback = document.getElementById("app") || document.querySelector("main");
    if (fallback) {
      fallback.innerHTML = `
        <section class="page-hero">
          <div class="eyebrow">Load Error</div>
          <h1>Site bootstrap failed</h1>
          <p>${error.message}</p>
        </section>
      `;
    }
  });
})();
