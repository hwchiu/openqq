# OpenQQ Agent Rules

This repository is a `K8s Sandbox Decision Lab` for Azure.

## Purpose

The goal is to decide which Kubernetes sandbox or runtime-guardrail solution is the best fit for agentic AI workloads.

This repo must provide:

1. a repeatable validation framework
2. a continuously updated official analysis
3. a defensible recommendation based on current evidence

## Fixed Baselines

Always reason about these as separate platform pairings:

1. `K8s 1.31 + CRI-O 1.31`
2. `K8s 1.34 + CRI-O 1.34`

## Candidate Solutions

1. `k8s + cri-o`
2. `k8s + OpenShell + cri-o`
3. `k8s + gVisor`
4. `k8s + OpenShell + gVisor`
5. `k8s + cri-o + KubeArmor`

## Decision Dimensions

Every recommendation must balance:

1. `Isolation and protection capability`
2. `Compatibility`
3. `Operational complexity`

## Evaluation Rules

- Never judge a candidate by default behavior alone.
- Use explicit guardrail, policy, runtime, or config declarations for comparisons.
- Every scenario should verify both `Allowed behavior` and `Blocked behavior`.
- `Install / bootstrap` failure is a valid negative result.
- If later scenarios cannot run because the solution failed earlier, mark them as `Blocked by solution failure`, not `N/A`.

## Scenario Families

The official scenario groups are:

1. `Baseline`
2. `Service Mesh`
3. `Filesystem Guardrails`
4. `Network Guardrails`
5. `Privilege Surface`
6. `Agentic AI Scenarios`

`Agentic AI Scenarios` must cover:

- workspace operations
- network usage
- sensitive resource access
- tool execution and privilege escalation
- policy robustness under real workload

## Output Model

The repo uses three output layers:

1. `Raw archive`
2. `Current state data`
3. `GitHub Pages analysis`

Do not create a brand-new standalone reader-facing report for every run unless explicitly requested.

## Official Reading Order

Remote readers should enter via GitHub Pages:

1. homepage current recommendation
2. baseline matrix
3. solution drill-downs
4. scenario drill-downs

## Maintenance Guidance

- Prefer updating current analysis pages over adding more historical prose.
- Keep raw evidence paths structured and traceable.
- Preserve explicit distinction between:
  - `Not tested`
  - `Blocked by solution failure`
  - `Executed and failed`
  - `Executed and passed`
