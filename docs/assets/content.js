window.OPENQQ_CONTENT = {
  repo: {
    name: "OpenQQ",
    branch: "main",
    home: "https://github.com/hwchiu/openqq",
    blobBase: "https://github.com/hwchiu/openqq/blob/main/"
  },
  header: {
    title: "OpenQQ Evidence Site",
    scope:
      "Evidence-backed comparison of runtime, sandbox, and policy-enforcement paths on a defined Kubernetes baseline."
  },
  summaryCards: [
    {
      title: "Recommended path",
      verdict: "OpenShell + runc is the current primary route.",
      body: "It is the only path in this rerun that keeps cluster baseline, Istio sidecar smoke, OpenShell control plane, and OpenShell guardrails aligned as PASS.",
      href: "tracks/openshell.html",
      linkLabel: "Open OpenShell track"
    },
    {
      title: "gVisor status",
      verdict: "Bare RuntimeClass gvisor remains unproven.",
      body: "Both gVisor routes keep failing the direct runtime probe and the Istio plus gVisor workload path on the 2026-06-09 baseline.",
      href: "tracks/gvisor.html",
      linkLabel: "Inspect gVisor status"
    },
    {
      title: "Istio baseline",
      verdict: "Control plane and standard sidecar smoke pass across all four environments.",
      body: "The current failure boundary is tied to runtimeClassName: gvisor, not to Istio control-plane installation or standard in-mesh traffic.",
      href: "tracks/istio.html",
      linkLabel: "Inspect Istio track"
    },
    {
      title: "KubeArmor boundary",
      verdict: "KubeArmor shows partial enforcement, not complete guardrails.",
      body: "Service-account token and file-read controls pass, while process and network enforcement remain failed in this rerun.",
      href: "tracks/kubearmor.html",
      linkLabel: "Inspect KubeArmor track"
    }
  ],
  unsupportedClaims: [
    {
      claim: "Bare RuntimeClass gvisor success cannot currently be claimed on the 2026-06-09 baseline.",
      href: "failures.html#failure-gvisor-runtime"
    },
    {
      claim: "Istio plus RuntimeClass gvisor readiness cannot currently be claimed on either gVisor route.",
      href: "failures.html#failure-istio-gvisor"
    },
    {
      claim: "KubeArmor cannot currently be described as complete runtime guardrails for process and network control.",
      href: "failures.html#failure-kubearmor"
    },
    {
      claim: "OpenShell plus gVisor should not be summarized as generally degraded; its current boundary is narrower and must be stated precisely.",
      href: "tracks/openshell.html#openshell-gvisor"
    }
  ],
  evidenceGroups: [
    {
      title: "Live matrix and summary reports",
      items: [
        {
          label: "Comparison Matrix Live Rerun - 2026-06-09",
          path: "testing/comparison-matrix-live-2026-06-09.md",
          note: "Primary high-level rerun summary and capability table."
        },
        {
          label: "Failure Catalog - 2026-06-09",
          path: "testing/failure-catalog-2026-06-09.md",
          note: "Direct failure evidence, log excerpts, and current interpretation."
        },
        {
          label: "Comparison Matrix README",
          path: "testing/matrix/README.md",
          note: "Explains the publish path for matrix results into docs data."
        }
      ]
    },
    {
      title: "Track-specific reports",
      items: [
        {
          label: "OpenShell runtime assessment",
          path: "testing/openshell-runtime-assessment-2026-06-03.md",
          note: "Broader OpenShell route narrative and evaluation context."
        },
        {
          label: "OpenShell architecture evidence",
          path: "testing/openshell-architecture-evidence-2026-06-03.md",
          note: "Architecture proof points behind the OpenShell path."
        },
        {
          label: "gVisor validation",
          path: "testing/openshell-gvisor-validation-2026-06-03.md",
          note: "Earlier gVisor route validation context."
        },
        {
          label: "KubeArmor hardening",
          path: "testing/kubearmor-hardening-2026-06-08.md",
          note: "KubeArmor enforcement and hardening details."
        },
        {
          label: "Istio impact - 2026-06-09",
          path: "testing/istio-impact-2026-06-09.md",
          note: "Current summary of Istio impact across the four environments."
        }
      ]
    },
    {
      title: "Published and raw artifacts",
      items: [
        {
          label: "Published matrix JSON for GitHub Pages",
          path: "docs/data/comparison-matrix.json",
          note: "Data source consumed by this site."
        },
        {
          label: "Live rerun summary JSON",
          path: "testing/raw/comparison-matrix-live-2026-06-09/summary.json",
          note: "Raw machine-readable result summary."
        },
        {
          label: "Latest matrix result policy",
          path: "testing/results/latest/README.md",
          note: "Explains why local latest results are not committed by default."
        }
      ]
    }
  ],
  tracks: [
    {
      slug: "openshell",
      title: "OpenShell Track",
      subtitle: "Current primary route for stable guardrails on the published baseline.",
      heroTag: "Recommended path",
      proven: [
        "OpenShell plus runc keeps control-plane readiness and guardrails at PASS on the 2026-06-09 baseline.",
        "OpenShell plus gVisor keeps OpenShell control plane and guardrails at PASS even though bare gVisor probe remains failed.",
        "Istio sidecar smoke does not immediately break the OpenShell paths in this rerun."
      ],
      notProven: [
        "OpenShell plus gVisor should not be generalized as a fully healthy gVisor route.",
        "The passing OpenShell guardrails path does not prove bare RuntimeClass gvisor success.",
        "The current evidence does not justify describing OpenShell plus gVisor as the default recommendation."
      ],
      interpretation:
        "OpenShell is the clearest positive result in the current material. The runc route remains the safest recommendation, while the gVisor route must be described more narrowly: OpenShell path PASS, bare gVisor route FAIL.",
      related: [
        "testing/openshell-runtime-assessment-2026-06-03.md",
        "testing/openshell-architecture-evidence-2026-06-03.md",
        "testing/comparison-matrix-live-2026-06-09.md"
      ]
    },
    {
      slug: "gvisor",
      title: "gVisor Track",
      subtitle: "Cluster baseline works, but direct gVisor workload claims still fail on the published rerun.",
      heroTag: "Unproven route",
      proven: [
        "Both gVisor environments keep nodes ready, baseline pods ready, and standard Istio sidecar smoke at PASS.",
        "The failure boundary is consistently tied to direct RuntimeClass gvisor and Istio plus gVisor workload readiness."
      ],
      notProven: [
        "Bare RuntimeClass gvisor success is not proven on this baseline.",
        "Istio plus RuntimeClass gvisor readiness is not proven on either gVisor route.",
        "OpenShell presence does not eliminate the bare gVisor failure pattern."
      ],
      interpretation:
        "The current evidence does not support broad positive claims about the gVisor route itself. The most accurate wording is that cluster baseline and general Istio function, while gVisor workload paths remain failed.",
      related: [
        "testing/openshell-gvisor-validation-2026-06-03.md",
        "testing/landlock-gvisor-root-cause-2026-06-03.md",
        "testing/comparison-matrix-live-2026-06-09.md",
        "testing/failure-catalog-2026-06-09.md"
      ]
    },
    {
      slug: "kubearmor",
      title: "KubeArmor Track",
      subtitle: "Selective enforcement works, but process and network claims are still overstated if described as complete guardrails.",
      heroTag: "Partial enforcement",
      proven: [
        "Service-account token access is blocked in the current rerun.",
        "Sensitive file reads are blocked in the current rerun.",
        "Istio control plane and standard sidecar smoke continue to pass on the KubeArmor route."
      ],
      notProven: [
        "Process enforcement is not proven because /usr/bin/sleep still executes successfully.",
        "Network enforcement is not proven because /usr/bin/curl still reaches HTTP 200.",
        "The route cannot currently be summarized as full runtime guardrails for agentic workloads."
      ],
      interpretation:
        "KubeArmor should be described as a route with clear wins on service-account and file controls, but with concrete remaining gaps on process and network enforcement in this baseline.",
      related: [
        "testing/kubearmor-hardening-2026-06-08.md",
        "testing/kubearmor-agentic-scenarios-2026-06-08.md",
        "testing/comparison-matrix-live-2026-06-09.md",
        "testing/failure-catalog-2026-06-09.md"
      ]
    },
    {
      slug: "istio",
      title: "Istio Track",
      subtitle: "Current evidence shows broad compatibility except where gVisor workload readiness is involved.",
      heroTag: "Broadly working baseline",
      proven: [
        "Istio 1.30.1 control plane installs and becomes ready across all four routes in the rerun.",
        "Standard sidecar injection and in-mesh traffic succeed across all four routes."
      ],
      notProven: [
        "Istio plus RuntimeClass gvisor readiness is not proven on either gVisor route.",
        "The evidence does not support blaming the Istio control plane for the gVisor workload failures."
      ],
      interpretation:
        "The current signal is that Istio itself is broadly working on the published baseline. The active incompatibility boundary is the combination of sidecar injection with RuntimeClass gvisor workloads.",
      related: [
        "testing/istio-impact-2026-06-09.md",
        "testing/comparison-matrix-live-2026-06-09.md",
        "testing/failure-catalog-2026-06-09.md"
      ]
    }
  ],
  failures: [
    {
      id: "failure-gvisor-runtime",
      title: "Bare RuntimeClass gvisor probe fails on both gVisor routes",
      verdict: "FAIL",
      detail:
        "The pod schedules and starts, but does not leave clean probe evidence such as a successful gVisor marker. This remains failed on both k3s-gvisor and k3s-openshell-gvisor.",
      evidence: [
        "testing/raw/comparison-matrix-live-2026-06-09/k3s-gvisor/gvisor-runtime.json",
        "testing/raw/comparison-matrix-live-2026-06-09/k3s-openshell-gvisor/gvisor-runtime.json",
        "testing/failure-catalog-2026-06-09.md"
      ]
    },
    {
      id: "failure-istio-gvisor",
      title: "Istio plus RuntimeClass gvisor workloads do not become ready",
      verdict: "FAIL",
      detail:
        "The direct error signal is a readiness timeout on both the server and client sides. Standard sidecar smoke still passes in the same environments, which narrows the problem boundary.",
      evidence: [
        "testing/raw/comparison-matrix-live-2026-06-09/k3s-gvisor/istio-gvisor-sidecar.json",
        "testing/raw/comparison-matrix-live-2026-06-09/k3s-openshell-gvisor/istio-gvisor-sidecar.json",
        "testing/failure-catalog-2026-06-09.md"
      ]
    },
    {
      id: "failure-kubearmor",
      title: "KubeArmor process and network enforcement remain failed",
      verdict: "FAIL",
      detail:
        "The current rerun still allows /usr/bin/sleep to execute and /usr/bin/curl to reach HTTP 200. File and service-account controls pass, so the issue is a boundary problem, not a total failure.",
      evidence: [
        "testing/raw/comparison-matrix-live-2026-06-09/k3s-kubearmor-runc/kubearmor-process-block.json",
        "testing/raw/comparison-matrix-live-2026-06-09/k3s-kubearmor-runc/kubearmor-network-block.json",
        "testing/failure-catalog-2026-06-09.md"
      ]
    }
  ]
};
