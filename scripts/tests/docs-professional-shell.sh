#!/usr/bin/env bash

set -euo pipefail

pages=(
  "docs/index.html"
  "docs/comparison-four-stacks.html"
  "docs/installs.html"
  "docs/matrix.html"
  "docs/report.html"
  "docs/lab.html"
  "docs/lab-gvisor.html"
  "docs/lab-kata.html"
  "docs/runbooks/agent-sandbox.html"
  "docs/runbooks/comparison-matrix-tests.html"
  "docs/runbooks/install-comparison-matrix.html"
  "docs/runbooks/install-k3s-gvisor.html"
  "docs/runbooks/install-k3s-kubearmor-runc.html"
  "docs/runbooks/install-k3s-openshell-gvisor.html"
  "docs/runbooks/install-k3s-openshell-runc.html"
  "docs/runbooks/k3s-cluster.html"
  "docs/runbooks/openshell.html"
)

required_patterns=(
  '<script>tailwind.config = { darkMode: '"'"'class'"'"' };<\/script>'
  '<script src="https://cdn.tailwindcss.com"><\/script>'
  '<link rel="stylesheet" href="(\.\./)?assets/reference.css">'
  '<script src="(\.\./)?assets/reference.js" defer><\/script>'
  'class="bg-slate-100 text-slate-900 dark:bg-slate-950 dark:text-slate-100"'
  'class="[^"]*page-hero'
  'class="[^"]*page-section'
  'class="[^"]*page-card'
  'class="theme-btn'
  'OpenShell Lab'
  'OpenShell Lab Professional Reference'
)

for page in "${pages[@]}"; do
  if [[ ! -f "${page}" ]]; then
    echo "missing page: ${page}" >&2
    exit 1
  fi

  for pattern in "${required_patterns[@]}"; do
    if ! grep -Eq "${pattern}" "${page}"; then
      echo "missing shared-shell pattern in ${page}: ${pattern}" >&2
      exit 1
    fi
  done

  if grep -q 'assets/site.css' "${page}"; then
    echo "legacy site.css shell still present in ${page}" >&2
    exit 1
  fi

  if grep -q '<style>' "${page}"; then
    echo "inline page-specific style block still present in ${page}" >&2
    exit 1
  fi
done

runbook_link_sources=(
  "docs/index.html"
  "docs/installs.html"
  "docs/matrix.html"
)

for page in "${runbook_link_sources[@]}"; do
  if grep -Eq 'github\.com/.*/docs/runbooks/.*\.md' "${page}"; then
    echo "runbook link still points to GitHub markdown in ${page}" >&2
    exit 1
  fi
done

echo "docs professional shell check passed"
