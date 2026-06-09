# K8s Sandbox Decision Lab Design

Date: 2026-06-09
Status: Draft approved in conversation, pending final user review of written spec

## Goal

Redefine this repository as a `K8s Sandbox Decision Lab` that runs on Azure and answers a practical decision question:

Which Kubernetes sandbox or runtime-guardrail solution is currently the best fit for agentic AI workloads?

This repository must do two things at the same time:

- provide a repeatable validation framework
- produce a decision-oriented recommendation based on current evidence

It is not just a collection of ad hoc labs and it is not just a generic documentation site.

## Core Output

The primary output of this repository is a decision record that can answer:

- which candidate solution is currently the strongest recommendation
- on which version baseline that recommendation holds
- which scenarios passed
- which scenarios failed
- whether failures came from weak protection, compatibility gaps, or operational cost

The secondary output is the reusable test framework that makes those conclusions repeatable.

## Decision Model

This is a balanced decision problem, not a single-axis security benchmark.

Each candidate must be assessed on three top-level dimensions:

1. `Isolation and protection capability`
2. `Compatibility`
3. `Operational complexity`

The final recommendation must balance all three.

## Fixed Version Baselines

Every candidate solution must be evaluated independently on these two platform baselines:

1. `K8s 1.31 + CRI-O 1.31`
2. `K8s 1.34 + CRI-O 1.34`

These are full platform pairings, not a single Kubernetes version with mixed CRI-O combinations.

All reporting, matrix summaries, and recommendation logic must preserve this distinction.

## Candidate Solutions

The comparison set currently includes five candidates:

1. `k8s + cri-o`
2. `k8s + OpenShell + cri-o`
3. `k8s + gVisor`
4. `k8s + OpenShell + gVisor`
5. `k8s + cri-o + KubeArmor`

These should be treated as first-class candidates in the evaluation matrix.

If a candidate cannot be provisioned, installed, or stabilized on a baseline, that is still a valid negative result for that candidate.

## Evaluation Principle: No Default-Behavior Guessing

The entire repository should follow one strict rule:

All candidates must be evaluated under explicit, declared guardrail configuration rather than implicit default behavior.

This applies across the board:

- OpenShell should be tested with explicit policy
- gVisor should be tested with explicit runtime and sandbox configuration
- KubeArmor should be tested with explicit scenario-specific policy
- Istio interactions should be tested with explicit mesh and injection setup

Success cannot mean:

- "the default happened to block it"
- "the default happened not to break it"
- "the candidate seemed okay without declared policy intent"

Instead, every scenario must verify both:

- `Allowed behavior`
- `Blocked behavior`

This is especially important for KubeArmor, where success must mean that the intended policy expresses the desired guardrail correctly and enforces it reliably.

## Evaluation Layers

Each candidate on each baseline should be evaluated through four ordered layers:

1. `Provision`
2. `Install / Bootstrap`
3. `Baseline Readiness`
4. `Scenario Results`

### Layer 1: Provision

Questions:

- Can the Azure infrastructure be created successfully?
- Can the Kubernetes cluster be created in a reproducible way?
- Are the required nodes, networking, and supporting resources available?

### Layer 2: Install / Bootstrap

Questions:

- Can the candidate solution be installed successfully?
- Do required controllers, daemons, runtime classes, or policy engines come up correctly?
- Can the route be bootstrapped without manual repair steps that fall outside the declared flow?

### Layer 3: Baseline Readiness

Questions:

- Are nodes ready?
- Can baseline pods run?
- Do core service, DNS, and basic workload operations function?
- Can optional but critical platform integrations such as Istio be added successfully where intended?

### Layer 4: Scenario Results

Questions:

- Does the candidate allow expected normal behavior?
- Does it block expected risky behavior?
- Does it maintain those properties under realistic agentic AI workload patterns?

## Failure Classification Rules

The repository must distinguish between these states clearly:

1. `Not tested`
2. `Blocked by solution failure`
3. `Executed and failed`
4. `Executed and passed`

This distinction is critical.

If a candidate fails at install or bootstrap:

- the later scenarios are not `N/A`
- they are `Blocked by solution failure`

This failure must count against at least:

- `Compatibility`
- `Operational complexity`

If a candidate cannot be installed, upgraded, stabilized, or brought to readiness, that is part of the evaluation result, not an external excuse.

## Scenario Families

The test framework should be organized into stable scenario families.

### 1. Baseline

Purpose:

- establish that the environment is functional enough to host workloads

Examples:

- node readiness
- basic pod execution
- service reachability
- DNS resolution
- storage sanity checks

### 2. Service Mesh

Purpose:

- measure compatibility with service-mesh integration, especially Istio

Examples:

- Istio control plane installation
- sidecar injection
- in-mesh traffic
- candidate plus Istio composition behavior

### 3. Filesystem Guardrails

Purpose:

- measure whether filesystem access is correctly constrained

Examples:

- workspace read access
- workspace write access where allowed
- write denial on protected paths
- sensitive file read denial
- mounted volume behavior
- temporary directory behavior

### 4. Network Guardrails

Purpose:

- measure whether network activity can be intentionally allowed or blocked

Examples:

- allowed outbound HTTP or HTTPS
- blocked outbound destinations
- DNS behavior
- cluster-internal service access
- TCP egress restrictions
- long-lived connection handling

### 5. Privilege Surface

Purpose:

- measure resistance to privilege escalation and access to sensitive platform resources

Examples:

- service account token access
- mounted secret access
- Kubernetes API permission discovery
- privileged container paths
- hostPath exposure
- runtime socket access
- elevated capability attempts

### 6. Agentic AI Scenarios

Purpose:

- model realistic agentic workloads rather than generic security toy cases

This family should be further divided into five subgroups.

#### 6.1 Workspace Operations

Examples:

- read repository files
- create files inside allowed workspace
- modify existing workspace files
- attempt to write outside the declared workspace
- attempt to write to protected system paths

#### 6.2 Network Usage

Examples:

- reach explicitly allowed external APIs
- fail to reach blocked destinations
- resolve DNS as required
- access internal cluster services when allowed
- test long-lived or callback-like network behavior where relevant

#### 6.3 Sensitive Resource Access

Examples:

- attempt to read service account tokens
- attempt to read mounted secrets or config
- attempt to inspect host-level sensitive paths
- attempt to enumerate Kubernetes API permissions
- attempt to access runtime-adjacent resources

#### 6.4 Tool Execution and Privilege Escalation

Examples:

- shell execution
- python execution
- curl usage
- package manager usage
- sudo or setuid attempts
- capability escalation attempts
- privileged namespace attempts
- special filesystem or mount attempts

#### 6.5 Policy Robustness Under Real Workload

Examples:

- verify agent tasks still work under active guardrails
- verify Istio plus guardrail composition where applicable
- verify policy reload or rollout consistency
- verify observability quality when actions are denied
- verify guardrails do not collapse during ordinary agent workflow

## Mapping Scenario Results To Decision Dimensions

The repository should map results into the three decision dimensions explicitly.

### Isolation and Protection Capability

Primarily informed by:

- Filesystem Guardrails
- Network Guardrails
- Privilege Surface
- blocked portions of Agentic AI Scenarios

Questions:

- Does the candidate block risky behavior correctly?
- Are the controls precise or blunt?
- Are there obvious escape or bypass paths?

### Compatibility

Primarily informed by:

- Provision
- Install / Bootstrap
- Baseline
- Service Mesh
- allowed portions of Agentic AI Scenarios

Questions:

- Can workloads actually run?
- Can Istio be layered on when required?
- Can the agent still do legitimate work?
- Does the solution fail in normal Kubernetes usage patterns?

### Operational Complexity

Primarily informed by:

- install burden
- policy authoring burden
- upgrade friction
- observability quality
- debugging cost
- number of special-case repair steps
- configuration fragility across baselines

Questions:

- How hard is this route to install and maintain?
- How hard is it to express the intended guardrails?
- How hard is it to reason about failure when something breaks?

## Reporting Rules

The repository should not reduce everything to raw pass or fail tables without interpretation.

Every report should preserve:

- candidate solution
- platform baseline
- evaluation layer
- scenario family
- allowed versus blocked intent
- outcome state
- concise interpretation

The final summary should be able to answer:

- strongest current recommendation
- strongest conditional recommendation
- most promising but unstable path
- strongest protection but weakest compatibility path
- lowest operational cost path

## Recommended Repository Direction

The repository structure and documentation should reflect the decision-lab purpose rather than the older narrow "four independent labs" framing.

At a minimum, future repo organization should make room for:

- baseline-specific stack definitions
- explicit scenario catalogs
- declared guardrail policies per candidate
- per-layer result collection
- decision summaries that compare candidates across both baselines

## Current Drift To Note

The current repository state shows signs of drift between:

- earlier documentation oriented around four stacks
- newer need for five candidates
- evolving platform baselines
- changing test material under `testing/`

That drift is not a reason to weaken the model.

Instead, it means the next implementation phase should realign repo structure, matrix definitions, and scenario catalogs to this decision-lab framing.

## Out Of Scope For This Spec

This spec does not yet define:

- exact file layout for the reworked repo
- exact JSON schema for matrix results
- exact scenario manifest format
- exact scoring formula or weighting values
- exact Azure deployment topology for every baseline

Those belong in the implementation-planning phase.

## Success Criteria

This repository direction is successful if:

- it can compare all five candidates on both baselines
- it distinguishes install failure from scenario failure cleanly
- it verifies explicit allowed and blocked behaviors rather than default behavior accidents
- it models realistic agentic AI workload concerns
- it can produce a recommendation that is defensible across protection, compatibility, and operational complexity
