(function () {
  const CONTENT = window.OPENQQ_CONTENT || {};
  const SOLUTION_PAGE_MAP = {
    "cri-o": "tracks/crio.html",
    "openshell-crio": "tracks/openshell.html",
    "gvisor": "tracks/gvisor.html",
    "openshell-gvisor": "tracks/openshell-gvisor.html",
    "kubearmor": "tracks/kubearmor.html"
  };

  function getRoot() {
    return document.body.dataset.root || ".";
  }

  function rootPath(path) {
    return `${getRoot()}/${path}`.replace("/./", "/");
  }

  function pageLink(path) {
    return rootPath(path);
  }

  function repoLink(path) {
    return `${CONTENT.repo.blobBase}${path}`;
  }

  async function loadCurrentState() {
    const response = await fetch(rootPath("data/current-state.json"));
    if (!response.ok) {
      throw new Error(`Failed to load current-state.json: ${response.status}`);
    }
    return response.json();
  }

  function getStatusClass(status) {
    switch (status) {
      case "PASS":
        return "status-pass";
      case "FAIL":
        return "status-fail";
      case "BLOCKED":
        return "status-blocked";
      case "PROVISIONAL":
        return "status-provisional";
      default:
        return "status-not-tested";
    }
  }

  function statusBadge(status) {
    return `<span class="status ${getStatusClass(status)}">${status}</span>`;
  }

  function renderSectionHeader(label, title, body) {
    return `
      <div class="section-header">
        <div>
          <div class="section-label">${label}</div>
          <h2>${title}</h2>
          <p>${body}</p>
        </div>
      </div>
    `;
  }

  function buildHeader() {
    const page = document.body.dataset.page;
    const nav = [
      ["home", pageLink("index.html"), CONTENT.nav.home],
      ["matrix", pageLink("matrix.html"), CONTENT.nav.matrix],
      ["tracks", pageLink("tracks/crio.html"), CONTENT.nav.tracks],
      ["scenarios", pageLink("failures.html"), CONTENT.nav.scenarios],
      ["evidence", pageLink("evidence.html"), CONTENT.nav.evidence]
    ];
    return `
      <div class="site-header-inner">
        <a class="brand" href="${pageLink("index.html")}">
          <span class="brand-kicker">K8s Sandbox Decision Lab</span>
          <span class="brand-title">${CONTENT.site.title}</span>
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

  function buildFooter(state) {
    return `
      <div class="site-footer-inner">
        <div>GitHub Pages 只維護目前最新官方分析。歷史 raw results 另存，不再當遠端閱讀主入口。</div>
        <div>Updated ${state.generatedAt} · <a class="footnote-link" href="${CONTENT.repo.home}">Repository</a></div>
      </div>
    `;
  }

  function byId(id) {
    return document.getElementById(id);
  }

  function findSolution(state, solutionId) {
    return state.solutions.find((item) => item.id === solutionId);
  }

  function renderCardGrid(cards) {
    return `
      <div class="card-grid">
        ${cards
          .map(
            (card) => `
              <article class="summary-card">
                <div class="section-label">${card.title}</div>
                <div class="verdict">${card.verdict}</div>
                <p>${card.body}</p>
                ${card.href ? `<a class="summary-link" href="${pageLink(card.href)}">${card.linkLabel}</a>` : ""}
              </article>
            `
          )
          .join("")}
      </div>
    `;
  }

  function renderHome(state) {
    byId("home-hero").innerHTML = `
      <section class="hero">
        <div>
          <div class="eyebrow">Current Recommendation</div>
          <h1>${state.recommendation.title}</h1>
          <p class="lede">${state.recommendation.summary}</p>
          <p>${state.recommendation.detail}</p>
        </div>
        <div class="meta-grid">
          <div class="meta-card"><span class="meta-label">目前結論</span><span class="meta-value">${state.recommendation.currentCall}</span></div>
          <div class="meta-card"><span class="meta-label">暫定主候選</span><span class="meta-value">${state.recommendation.solutionLabel}</span></div>
          <div class="meta-card"><span class="meta-label">最新更新</span><span class="meta-value">${state.generatedAt}</span></div>
          <div class="meta-card"><span class="meta-label">閱讀模型</span><span class="meta-value">Current analysis + raw archive</span></div>
        </div>
      </section>
    `;

    byId("current-assessment").innerHTML =
      renderSectionHeader("總覽", "目前官方判讀", "首頁先回答現在該選誰，再往下拆 baseline、solution 與 scenario。") +
      renderCardGrid([
        {
          title: "目前推薦",
          verdict: state.recommendation.solutionLabel,
          body: state.recommendation.why,
          href: SOLUTION_PAGE_MAP[state.recommendation.solutionId],
          linkLabel: "查看 solution 判讀"
        },
        {
          title: "版本基線",
          verdict: "兩條固定配對基線",
          body: "K8s 1.31 + CRI-O 1.31 與 K8s 1.34 + CRI-O 1.34 必須分開判讀。",
          href: "matrix.html",
          linkLabel: "查看基線矩陣"
        },
        {
          title: "評估方式",
          verdict: "Allowed / Blocked 都要驗證",
          body: "所有候選都必須在明確宣告的 guardrail / policy / config 下比較。",
          href: "evidence.html",
          linkLabel: "查看方法與資料"
        },
        {
          title: "阻塞定義",
          verdict: `${state.overview.blockedCandidates} 個候選目前 blocked`,
          body: state.overview.blockedSummary,
          href: "failures.html",
          linkLabel: "查看情境與風險"
        }
      ]);

    byId("baseline-summary").innerHTML =
      renderSectionHeader("Baselines", "兩條固定平台基線", "每個候選都必須在兩條完整平台配對上獨立評估。") +
      `<div class="card-grid">
        ${state.baselines
          .map(
            (baseline) => `
              <article class="summary-card">
                <div class="section-label">${baseline.id}</div>
                <div class="verdict">${baseline.label}</div>
                <p>${baseline.summary}</p>
                <ul class="facts-list">${baseline.highlights.map((item) => `<li>${item}</li>`).join("")}</ul>
              </article>
            `
          )
          .join("")}
      </div>`;

    byId("scenario-summary").innerHTML =
      renderSectionHeader("Scenarios", "情境族群", "不再用混亂測試紀錄閱讀 repo，而是用固定 scenario families 來組織判讀。") +
      `<div class="card-grid">
        ${state.scenarios
          .map(
            (scenario) => `
              <article class="summary-card">
                <div class="section-label">${scenario.id}</div>
                <div class="verdict">${scenario.name}</div>
                <p>${scenario.focus}</p>
              </article>
            `
          )
          .join("")}
      </div>`;

    byId("methodology-summary").innerHTML =
      renderSectionHeader("Method", "資料與文件流程", "遠端閱讀以 Pages 為主，raw archive 為追溯層，current-state 為官方資料層。") +
      `<article class="page-section"><ul class="claim-list">${state.methodology
        .map((item) => `<li>${item}</li>`)
        .join("")}</ul></article>`;
  }

  function renderMatrix(state) {
    byId("matrix-overview").innerHTML = `
      <section class="page-hero">
        <div class="page-title-row">
          <div>
            <div class="eyebrow">Baseline View</div>
            <h1>基線矩陣</h1>
          </div>
          <div class="page-tag">recommendation-first, baseline-aware</div>
        </div>
        <p>任何 install / bootstrap 失敗都應標為 BLOCKED，而不是 N/A。這一頁呈現目前官方狀態，不代表完整歷史 run。</p>
      </section>
    `;

    byId("matrix-table").innerHTML = `
      <article class="page-section">
        <div class="matrix-scroll">
          <table>
            <thead>
              <tr>
                <th>Solution</th>
                ${state.baselines.map((baseline) => `<th>${baseline.label}</th>`).join("")}
                <th>Drill-down</th>
              </tr>
            </thead>
            <tbody>
              ${state.solutions
                .map(
                  (solution) => `
                    <tr>
                      <td class="track-cell">
                        <strong>${solution.label}</strong>
                        <span>${solution.summary}</span>
                      </td>
                      ${state.baselines
                        .map(
                          (baseline) => `
                            <td>
                              ${statusBadge(solution.baselineStatus[baseline.id].status)}
                              <div class="status-note">${solution.baselineStatus[baseline.id].note}</div>
                            </td>
                          `
                        )
                        .join("")}
                      <td><a class="inline-link" href="${pageLink(SOLUTION_PAGE_MAP[solution.id])}">查看</a></td>
                    </tr>
                  `
                )
                .join("")}
            </tbody>
          </table>
        </div>
      </article>
    `;
  }

  function renderScenarios(state) {
    byId("failures-hero").innerHTML = `
      <section class="page-hero">
        <div class="page-title-row">
          <div>
            <div class="eyebrow">Scenario View</div>
            <h1>情境與風險判讀</h1>
          </div>
          <div class="page-tag">allowed / blocked / blocked by solution failure</div>
        </div>
        <p>這一頁用 scenario 視角解釋未來要怎麼讀 solution 的成敗，而不是把它當單純 failures dump。</p>
      </section>
    `;

    byId("failures-body").innerHTML = `
      <div class="failure-grid">
        ${state.scenarios
          .map(
            (scenario) => `
              <article class="failure-card">
                <div class="section-label">${scenario.id}</div>
                <h3>${scenario.name}</h3>
                <p>${scenario.focus}</p>
                <ul class="failure-list">
                  ${scenario.currentRead.map((item) => `<li>${item}</li>`).join("")}
                </ul>
              </article>
            `
          )
          .join("")}
      </div>
    `;
  }

  function renderEvidence(state) {
    byId("evidence-hero").innerHTML = `
      <section class="page-hero">
        <div class="page-title-row">
          <div>
            <div class="eyebrow">Methodology</div>
            <h1>方法、資料與更新規則</h1>
          </div>
          <div class="page-tag">official remote reading path</div>
        </div>
        <p>這裡定義資料層與官方閱讀順序，避免未來又退化回「很多 testing 文件但沒人知道哪份才是最新結論」。</p>
      </section>
    `;

    byId("evidence-body").innerHTML = `
      <article class="page-section">
        <div class="callout">Raw archive 全保留、current-state 只保存最新官方狀態、Pages 持續更新同一份正式分析。</div>
      </article>
      <div class="evidence-grid">
        ${state.outputModel
          .map(
            (item) => `
              <article class="evidence-group">
                <div class="section-label">${item.title}</div>
                <h3>${item.path}</h3>
                <p>${item.body}</p>
              </article>
            `
          )
          .join("")}
      </div>
      <article class="page-section">
        <div class="section-label">Repo documents</div>
        <ul class="evidence-list">
          <li><a href="${repoLink("README.md")}">README.md</a></li>
          <li><a href="${repoLink("AGENTS.md")}">AGENTS.md</a></li>
          <li><a href="${repoLink("CLAUDE.md")}">CLAUDE.md</a></li>
          <li><a href="${repoLink("docs/runbooks/decision-lab-workflow.md")}">Decision Lab workflow</a></li>
          <li><a href="${repoLink("docs/runbooks/experiment-design-template.md")}">Experiment design template</a></li>
          <li><a href="${repoLink("docs/reports/2026-06-10-initial-baseline-status.md")}">Initial baseline status report</a></li>
          <li><a href="${repoLink("docs/reports/2026-06-10-crio-family-cilium-baseline-switch.md")}">CRI-O family Cilium baseline switch</a></li>
          <li><a href="${repoLink("docs/reports/2026-06-11-k3s-crio-cilium-baseline-success.md")}">Plain CRI-O 1.31 Cilium baseline success</a></li>
          <li><a href="${repoLink("docs/reports/2026-06-11-k3s-crio-134-cilium-baseline-success.md")}">Plain CRI-O 1.34 Cilium baseline success</a></li>
          <li><a href="${repoLink("docs/reports/2026-06-12-k3s-openshell-runc-cilium-success.md")}">OpenShell + CRI-O 1.31 Cilium success</a></li>
          <li><a href="${repoLink("docs/reports/2026-06-12-k3s-openshell-runc-134-cilium-success.md")}">OpenShell + CRI-O 1.34 Cilium success</a></li>
          <li><a href="${repoLink("docs/reports/2026-06-12-k3s-gvisor-cilium-failures.md")}">gVisor Cilium failure report</a></li>
          <li><a href="${repoLink("docs/reports/2026-06-12-k3s-kubearmor-runc-cilium-131-policy-results.md")}">KubeArmor 1.31 policy results</a></li>
          <li><a href="${repoLink("docs/reports/2026-06-12-k3s-kubearmor-runc-134-cilium-policy-results.md")}">KubeArmor 1.34 policy results</a></li>
          <li><a href="${repoLink("docs/reports/2026-06-10-k3s-crio-baseline-failure.md")}">Plain CRI-O 1.31 first failure report</a></li>
          <li><a href="${repoLink("docs/reports/2026-06-10-k3s-crio-baseline-recovery.md")}">Plain CRI-O 1.31 recovery report</a></li>
          <li><a href="${repoLink("docs/reports/2026-06-10-k3s-crio-134-baseline-failure.md")}">Plain CRI-O 1.34 first failure report</a></li>
          <li><a href="${repoLink("docs/reports/2026-06-10-k3s-crio-134-baseline-recovery.md")}">Plain CRI-O 1.34 recovery report</a></li>
          <li><a href="${repoLink("docs/reports/2026-06-10-k3s-openshell-runc-134-bootstrap-blocked.md")}">OpenShell + CRI-O 1.34 blocked report</a></li>
          <li><a href="${repoLink("docs/reports/2026-06-10-k3s-gvisor-134-runtime-failure.md")}">gVisor 1.34 runtime verify report</a></li>
          <li><a href="${repoLink("docs/superpowers/specs/2026-06-09-k8s-sandbox-decision-lab-design.md")}">Decision Lab design spec</a></li>
          <li><a href="${repoLink("docs/superpowers/specs/2026-06-10-crio-family-cilium-baseline-design.md")}">CRI-O family Cilium baseline spec</a></li>
        </ul>
      </article>
    `;
  }

  function renderTrack(state) {
    const solutionId = document.body.dataset.track;
    const solution = findSolution(state, solutionId);
    if (!solution) {
      byId("track-hero").innerHTML = `<section class="page-hero"><h1>Solution not found</h1></section>`;
      return;
    }

    byId("track-hero").innerHTML = `
      <section class="page-hero">
        <div class="page-title-row">
          <div>
            <div class="eyebrow">${solution.category}</div>
            <h1>${solution.label}</h1>
          </div>
          <div class="page-tag">${solution.currentCall}</div>
        </div>
        <p>${solution.interpretation}</p>
      </section>
    `;

    byId("track-body").innerHTML = `
      <div class="card-grid">
        ${state.baselines
          .map(
            (baseline) => `
              <article class="summary-card">
                <div class="section-label">${baseline.label}</div>
                <div class="verdict">${statusBadge(solution.baselineStatus[baseline.id].status)}</div>
                <p>${solution.baselineStatus[baseline.id].note}</p>
              </article>
            `
          )
          .join("")}
      </div>
      <article class="track-summary">
        <div class="section-label">Summary</div>
        <p>${solution.summary}</p>
      </article>
      <div class="split">
        <article class="fact-card">
          <div class="section-label">Dimensions</div>
          <ul class="facts-list">${solution.dimensionRead.map((item) => `<li>${item}</li>`).join("")}</ul>
        </article>
        <article class="fact-card">
          <div class="section-label">Scenario Read</div>
          <ul class="facts-list">${solution.scenarioRead.map((item) => `<li>${item}</li>`).join("")}</ul>
        </article>
      </div>
    `;
  }

  async function initPage() {
    const state = await loadCurrentState();
    byId("app");
    document.querySelector(".site-header").innerHTML = buildHeader();
    document.querySelector(".site-footer").innerHTML = buildFooter(state);

    switch (document.body.dataset.page) {
      case "home":
        renderHome(state);
        break;
      case "matrix":
        renderMatrix(state);
        break;
      case "scenarios":
        renderScenarios(state);
        break;
      case "evidence":
        renderEvidence(state);
        break;
      case "track":
        renderTrack(state);
        break;
      default:
        break;
    }
  }

  initPage().catch((error) => {
    const app = document.getElementById("app") || document.querySelector("main");
    if (app) {
      app.innerHTML = `
        <section class="page-hero">
          <div class="eyebrow">Load Error</div>
          <h1>Current analysis bootstrap failed</h1>
          <p>${error.message}</p>
        </section>
      `;
    }
  });
})();
