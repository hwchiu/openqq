# Istio Comparison Runbook

這份 runbook 只描述四套比較環境如何安裝與重跑 Istio 驗證。最新結果請看：

- [testing/istio-impact-2026-06-09.md](/Users/hwchiu/hwchiu/openqq/testing/istio-impact-2026-06-09.md)

## 安裝到四套環境

```bash
./scripts/install-istio-comparison.sh
```

## 重跑三類 Istio 測試

### 1. control plane

```bash
./scripts/tests/istio-control-plane.sh generated/stacks/k3s-gvisor/kubeconfig
./scripts/tests/istio-control-plane.sh generated/stacks/k3s-openshell-runc/kubeconfig
./scripts/tests/istio-control-plane.sh generated/stacks/k3s-openshell-gvisor/kubeconfig
./scripts/tests/istio-control-plane.sh generated/stacks/k3s-kubearmor-runc/kubeconfig
```

### 2. 一般 sidecar smoke

```bash
./scripts/tests/istio-sidecar-smoke.sh generated/stacks/k3s-gvisor/kubeconfig k3s-gvisor
./scripts/tests/istio-sidecar-smoke.sh generated/stacks/k3s-openshell-runc/kubeconfig k3s-openshell-runc
./scripts/tests/istio-sidecar-smoke.sh generated/stacks/k3s-openshell-gvisor/kubeconfig k3s-openshell-gvisor
./scripts/tests/istio-sidecar-smoke.sh generated/stacks/k3s-kubearmor-runc/kubeconfig k3s-kubearmor-runc
```

### 3. `RuntimeClass gvisor` + sidecar

```bash
./scripts/tests/istio-gvisor-sidecar.sh generated/stacks/k3s-gvisor/kubeconfig k3s-gvisor
./scripts/tests/istio-gvisor-sidecar.sh generated/stacks/k3s-openshell-gvisor/kubeconfig k3s-openshell-gvisor
```

## 06-09 最新結論

- 四套 `istiod` 都 ready
- 四套一般 sidecar smoke 都 PASS
- 兩套 gVisor 路線的 `RuntimeClass gvisor` + sidecar 都 FAIL
- `OpenShell + runc` 與 `OpenShell + gVisor` 在 Istio 後都維持 guardrails PASS
