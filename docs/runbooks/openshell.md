# OpenShell Runbook

## 元件

1. `agent-sandbox` controller + CRD
2. `openshell` Helm release
3. sandbox patcher (`runc` 或 `gvisor` 路線)

## 06-09 在四環境中的最新結果

### `k3s-openshell-runc`

- `openshell-control-plane`: PASS
- `openshell-guardrails`: PASS
- `istio-sidecar-smoke`: PASS

### `k3s-openshell-gvisor`

- `openshell-control-plane`: PASS
- `openshell-guardrails`: PASS
- `gvisor-runtime`: FAIL
- `istio-gvisor-sidecar`: FAIL

## 重要說明

1. OpenShell 自身路徑在 `runc` 主線仍最穩定。
2. `gvisor` 路線這輪的 OpenShell guardrails 有通過，但不代表 bare gVisor workload 已穩。
3. 目前 repo 仍依賴 Kubernetes-side patcher，將 OpenShell sandbox 調整到需要的 `privileged` / runtimeClass 狀態。

## 參考報告

- [testing/comparison-matrix-live-2026-06-09.md](/Users/hwchiu/hwchiu/openqq/testing/comparison-matrix-live-2026-06-09.md)
- [testing/istio-impact-2026-06-09.md](/Users/hwchiu/hwchiu/openqq/testing/istio-impact-2026-06-09.md)
