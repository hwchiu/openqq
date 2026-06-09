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
)

required_patterns=(
  '<script>tailwind.config = { darkMode: '"'"'class'"'"' };<\/script>'
  '<script src="https://cdn.tailwindcss.com"><\/script>'
  '<link rel="stylesheet" href="assets/reference.css">'
  '<script src="assets/reference.js" defer><\/script>'
  'class="bg-slate-100 text-slate-900 dark:bg-slate-950 dark:text-slate-100"'
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
done

echo "docs professional shell check passed"
