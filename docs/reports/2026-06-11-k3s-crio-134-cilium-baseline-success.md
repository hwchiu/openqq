# K3s + CRI-O 1.34 + Cilium Baseline Success - 2026-06-11

這份紀錄對應 `k3s-crio-134` 在 `K8s 1.34 + CRI-O 1.34` 上，改用正式 `Cilium` baseline 後的第一次完整 live success。

這次驗證使用的是乾淨重建後的 stack，而不是沿用舊 control plane / worker 組合。這很重要，因為中途曾觀察到：

- 只重建 control plane 會讓舊 worker 保留舊 CA
- worker 對新的 API server 會報 `x509: certificate signed by unknown authority`

因此這份 success 只採計 `full destroy + clean recreate` 後的結果。

## 測試基線

- `K8s 1.34 + CRI-O 1.34`
- Stack: `k3s-crio-134`

## 這次驗證的重點

1. `1.34/1.34` 是否也能在 `no-flannel + Cilium` 上穩定建立三節點叢集
2. `Cilium` 是否能成功讓全部節點轉 `Ready`
3. baseline workload 是否可執行
4. `Istio control plane` 是否可正常啟動

## 執行項目

1. `nodes-ready`
2. `baseline-pod`
3. `istio-control-plane`

## 結果

- `nodes-ready`: PASS
- `baseline-pod`: PASS
- `istio-control-plane`: PASS

## 關鍵 debug 結果

這次除了共用 `1.31` 那兩個修正外，還多確認了一點：

- `1.34` 如果只是 replacement 部分節點，會留下 CA 不一致的污染狀態
- 所以正式驗證必須以 `full destroy + clean recreate` 的 stack 為準

## Decision Lab 判讀

這次結果代表：

1. `K3s + CRI-O + Cilium` 不只在 `1.31/1.31` 成立，也在 `1.34/1.34` 成立
2. plain CRI-O 的兩條正式平台 baseline 都已經有 `baseline + Istio` 的 live success
3. 後續 `OpenShell`、`gVisor`、`KubeArmor` 的 1.34 驗證，現在可以建立在乾淨有效的 baseline 上

## Raw evidence

對應原始輸出位於：

- `records/raw/2026-06-11/k3s-crio-cilium-134/`

主要檔案：

- `nodes-ready.json`
- `baseline-pod.json`
- `istio-control-plane.json`
- `nodes-wide.txt`
- `kube-system-pods.txt`
