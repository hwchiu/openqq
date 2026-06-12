# K3s + OpenShell + CRI-O + Cilium Success - 2026-06-12

這份紀錄對應 `k3s-openshell-runc` 在 `K8s 1.31 + CRI-O 1.31` 上，建立在正式 `Cilium` baseline 之上的完整 live success。

這不是沿用舊的 `Flannel workaround` 結論，而是在新的正式比較模型下，重新驗證：

- `K3s --flannel-backend=none`
- `CRI-O`
- `Cilium`
- `OpenShell`

## 測試基線

- `K8s 1.31 + CRI-O 1.31`
- Stack: `k3s-openshell-runc`

## 這次驗證的重點

1. 三節點叢集是否維持 `Ready`
2. baseline workload 是否可執行
3. `OpenShell control plane` 是否正常
4. `OpenShell guardrails` 是否同時守住 allowed / blocked 行為
5. `Service Mesh / Istio` 是否仍能正常疊加

## 執行項目

1. `nodes-ready`
2. `baseline-pod`
3. `openshell-control-plane`
4. `openshell-guardrails`
5. `istio-control-plane`
6. `istio-sidecar-smoke`

## 結果

- `nodes-ready`: PASS
- `baseline-pod`: PASS
- `openshell-control-plane`: PASS
- `openshell-guardrails`: PASS
- `istio-control-plane`: PASS
- `istio-sidecar-smoke`: PASS

## 關鍵判讀

這次結果代表：

1. `OpenShell + CRI-O` 在 `1.31/1.31` 上不只是 control plane 存活，而是 guardrails 與 mesh 疊加都成立
2. 這條候選已經在正式 `Cilium` baseline 上拿到完整正面證據
3. 先前的歷史結果可以保留，但 current recommendation 應以這次 live success 為主

## Raw evidence

對應原始輸出位於：

- `records/raw/2026-06-12/k3s-openshell-runc-cilium/`
- `testing/raw/matrix-k3s-openshell-runc-1781265523/`

主要檔案：

- `nodes-ready.json`
- `baseline-pod.json`
- `openshell-control-plane.json`
- `openshell-guardrails.json`
- `istio-control-plane.json`
- `istio-sidecar-smoke.json`
