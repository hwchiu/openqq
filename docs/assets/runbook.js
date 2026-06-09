(function () {
  const REPO_ROOTS = [
    '/Users/hwchiu/hwchiu/openqq/',
    '/home/ubuntu/openqq/'
  ];

  function loadMarked() {
    if (window.marked) {
      return Promise.resolve();
    }

    return new Promise((resolve, reject) => {
      const script = document.createElement('script');
      script.src = 'https://cdn.jsdelivr.net/npm/marked/marked.min.js';
      script.onload = resolve;
      script.onerror = () => reject(new Error('failed to load markdown renderer'));
      document.head.appendChild(script);
    });
  }

  function slugify(text) {
    return text
      .toLowerCase()
      .trim()
      .replace(/[^\w\u4e00-\u9fff-]+/g, '-')
      .replace(/^-+|-+$/g, '')
      .replace(/-{2,}/g, '-');
  }

  function rewriteHref(href) {
    if (!href || href.startsWith('#') || /^https?:\/\//.test(href)) {
      return href;
    }

    for (const prefix of REPO_ROOTS) {
      if (href.startsWith(prefix)) {
        return `https://github.com/hwchiu/openqq/blob/main/${href.slice(prefix.length)}`;
      }
    }

    if (href.startsWith('docs/runbooks/')) {
      return href.replace(/^docs\/runbooks\//, '').replace(/\.md$/, '.html');
    }

    if (href.endsWith('.md')) {
      return href.replace(/\.md$/, '.html');
    }

    return href;
  }

  function markActiveNav() {
    const nav = document.body.dataset.nav;
    if (!nav) {
      return;
    }

    document.querySelectorAll('[data-nav-link]').forEach((link) => {
      const isActive = link.dataset.navLink === nav;
      link.classList.toggle('nav-active', isActive);
      link.classList.toggle('nav-link', !isActive);
    });
  }

  function fillMetadata() {
    const body = document.body;
    const title = body.dataset.runbookTitle || '';
    const lead = body.dataset.runbookLead || '';
    const kicker = body.dataset.runbookKicker || '';
    const source = body.dataset.runbookSrc || '';
    const backHref = body.dataset.runbookBackHref || '../index.html';
    const backLabel = body.dataset.runbookBackLabel || 'Back';

    document.title = `${title} · OpenShell Lab`;

    const titleNode = document.getElementById('runbook-title');
    const leadNode = document.getElementById('runbook-lead');
    const kickerNode = document.getElementById('runbook-kicker-text');
    const sourceNode = document.getElementById('runbook-source');
    const backNode = document.getElementById('runbook-back');

    if (titleNode) {
      titleNode.textContent = title;
    }
    if (leadNode) {
      leadNode.textContent = lead;
    }
    if (kickerNode) {
      kickerNode.textContent = kicker;
    }
    if (sourceNode) {
      sourceNode.textContent = `docs/runbooks/${source}`;
    }
    if (backNode) {
      backNode.href = backHref;
      backNode.textContent = backLabel;
    }
  }

  function renderToc(container, headings) {
    if (!container) {
      return;
    }

    if (!headings.length) {
      container.innerHTML = '<div class="page-note">No section headings were found in this runbook.</div>';
      return;
    }

    const items = headings.map((heading) => {
      const isSubheading = heading.tagName === 'H3';
      return `
        <a href="#${heading.id}" class="toc-link block ${isSubheading ? 'pl-4 text-xs' : 'text-sm'}">
          ${heading.textContent}
        </a>
      `;
    }).join('');

    container.innerHTML = items;
  }

  async function renderRunbook() {
    const body = document.body;
    const source = body.dataset.runbookSrc;
    const content = document.getElementById('runbook-content');
    const toc = document.getElementById('runbook-toc');

    if (!source || !content) {
      return;
    }

    try {
      await loadMarked();
      const response = await fetch(source);
      if (!response.ok) {
        throw new Error(`failed to load ${source}: ${response.status}`);
      }

      const markdown = await response.text();
      window.marked.setOptions({
        gfm: true,
        breaks: false,
        headerIds: false,
        mangle: false
      });

      content.innerHTML = window.marked.parse(markdown);

      const firstHeading = content.querySelector('h1');
      if (firstHeading) {
        firstHeading.remove();
      }

      const headings = Array.from(content.querySelectorAll('h2, h3'));
      headings.forEach((heading, index) => {
        heading.id = heading.id || `section-${index + 1}-${slugify(heading.textContent)}`;
      });

      content.querySelectorAll('a[href]').forEach((link) => {
        const rawHref = link.getAttribute('href');
        const nextHref = rewriteHref(rawHref);
        link.setAttribute('href', nextHref);
        if (/^https?:\/\//.test(nextHref)) {
          link.setAttribute('target', '_blank');
          link.setAttribute('rel', 'noreferrer');
        }
      });

      renderToc(toc, headings);
    } catch (error) {
      content.innerHTML = `
        <div class="page-note">
          Failed to render this runbook: ${error.message}
        </div>
      `;
      renderToc(toc, []);
    }
  }

  document.addEventListener('DOMContentLoaded', async () => {
    fillMetadata();
    markActiveNav();
    await renderRunbook();
  });
})();
