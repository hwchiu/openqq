# K3s + OpenShell + CRI-O 1.34 + Cilium Success - 2026-06-12

這份紀錄對應 `k3s-openshell-runc-134` 在 `K8s 1.34 + CRI-O 1.34` 上，建立在正式 `Cilium` baseline 之上的完整 live success。

這次結果刻意不採計先前 `partial control-plane replacement` 的污染狀態。當時兩台舊 worker 都出現：

- `tls: failed to verify certificate: x509: certificate signed by unknown authority`

因此這份 success 是以乾淨 stack 為準，並直接讀取目前仍存活的 live cluster 狀態。

## 測試基線

- `K8s 1.34 + CRI-O 1.34`
- Stack: `k3s-openshell-runc-134`

## 這次驗證的重點

1. 三節點叢集是否維持 `Ready`
2. baseline workload 是否可執行
3. `OpenShell control plane` 是否正常
4. `OpenShell guardrails` 是否同時守住 allowed / blocked 行為
5. 在安裝 `Istio` 後，mesh control plane 與 sidecar smoke 是否仍能成立

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

## 關鍵 debug 判讀

這次除了正面結果外，也明確留下了一個重要規則：

1. `1.34` 基線若只替換 control plane，舊 worker 會殘留舊 CA
2. 這類結果不能算成 `OpenShell fail`
3. 正式判讀必須建立在 `full destroy + clean recreate` 或等價的乾淨 stack 之上

## Decision Lab 判讀

這次結果代表：

1. `OpenShell + CRI-O` 不只在 `1.31/1.31` 成立，也在 `1.34/1.34` 成立
2. 這條候選已經同時證明 `baseline`、`OpenShell guardrails`、`Service Mesh / Istio`
3. 舊的 `1.34 blocked` 報告應保留為歷史 debug 證據，但不再代表 current state

## Raw evidence

對應原始輸出位於：

- `records/raw/2026-06-12/k3s-openshell-runc-134-cilium/`
- `testing/raw/matrix-k3s-openshell-runc-134-1781265344/`

主要檔案：

- `nodes-ready.json`
- `baseline-pod.json`
- `openshell-control-plane.json`
- `openshell-guardrails.json`
- `istio-control-plane.json`
- `istio-sidecar-smoke.json`
