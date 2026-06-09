# OpenQQ K8s Sandbox Decision Lab

This repository is a `K8s Sandbox Decision Lab` for Azure.

Its purpose is to compare candidate Kubernetes sandbox or runtime-guardrail solutions and answer a practical decision question:

Which solution is currently the best fit for agentic AI workloads?

This repo must provide:

1. a repeatable validation framework
2. a continuously updated official analysis
3. a defensible recommendation based on current evidence

## Fixed baselines

Every candidate must be evaluated independently on these two platform pairings:

1. `K8s 1.31 + CRI-O 1.31`
2. `K8s 1.34 + CRI-O 1.34`

## Candidate solutions

1. `k8s + cri-o`
2. `k8s + OpenShell + cri-o`
3. `k8s + gVisor`
4. `k8s + OpenShell + gVisor`
5. `k8s + cri-o + KubeArmor`

## Decision dimensions

Every recommendation must balance:

1. `Isolation and protection capability`
2. `Compatibility`
3. `Operational complexity`

## Fast entry points

1. Current analysis homepage: [docs/index.html](/Users/hwchiu/hwchiu/openqq/docs/index.html)
2. Baseline matrix: [docs/matrix.html](/Users/hwchiu/hwchiu/openqq/docs/matrix.html)
3. Scenario view: [docs/failures.html](/Users/hwchiu/hwchiu/openqq/docs/failures.html)
4. Methodology and data model: [docs/evidence.html](/Users/hwchiu/hwchiu/openqq/docs/evidence.html)
5. Decision Lab design spec: [docs/superpowers/specs/2026-06-09-k8s-sandbox-decision-lab-design.md](/Users/hwchiu/hwchiu/openqq/docs/superpowers/specs/2026-06-09-k8s-sandbox-decision-lab-design.md)
6. One-shot installer: [scripts/install-comparison-matrix.sh](/Users/hwchiu/hwchiu/openqq/scripts/install-comparison-matrix.sh)
7. One-shot test runner: [scripts/run-comparison-matrix-tests.sh](/Users/hwchiu/hwchiu/openqq/scripts/run-comparison-matrix-tests.sh)
8. One-shot destroy: [scripts/destroy-comparison-matrix.sh](/Users/hwchiu/hwchiu/openqq/scripts/destroy-comparison-matrix.sh)

## Output model

This repo now aims for three output layers:

1. `Raw archive`
   Historical raw results kept for traceability and debugging.

2. `Current state data`
   Latest official machine-readable status for GitHub Pages.

3. `GitHub Pages analysis`
   A continuously updated official reading path, not a pile of one-report-per-run pages.

## Evaluation rules

- Compare candidates under explicit guardrail, policy, runtime, or config declarations.
- Do not use default behavior as the success criterion.
- Validate both `Allowed behavior` and `Blocked behavior`.
- Treat install/bootstrap failure as a real negative result.
- If later scenarios cannot run because a solution failed earlier, classify them as `Blocked by solution failure`.

## Notes

- Each stack has its own Terraform root and state file.
- Each stack writes kubeconfig under `generated/stacks/<stack-name>/kubeconfig`.
- The matrix installer can still be used as the orchestration entry point.
- The Pages site should read latest official state from `docs/data/current-state.json`.
