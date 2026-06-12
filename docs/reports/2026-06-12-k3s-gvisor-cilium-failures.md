# K3s + gVisor + Cilium Failures - 2026-06-12

這份紀錄整理 `k3s-gvisor` 與 `k3s-gvisor-134` 在正式 `Cilium` baseline 上的最新 live 結果。

這次不是歷史 `Flannel` wiring 的延伸觀察，而是針對目前正式比較模型下的重新驗證：

- `K3s --flannel-backend=none`
- `CRI-O`
- `Cilium`
- `RuntimeClass gvisor`

## 測試基線

- `K8s 1.31 + CRI-O 1.31`
- `K8s 1.34 + CRI-O 1.34`

## 1.31/1.31 結果

Stack: `k3s-gvisor`

執行項目：

1. `nodes-ready`
2. `baseline-pod`
3. `gvisor-runtime`
4. `istio-control-plane`
5. `istio-gvisor-sidecar`

結果：

- `nodes-ready`: PASS
- `baseline-pod`: PASS
- `gvisor-runtime`: FAIL
- `istio-control-plane`: PASS
- `istio-gvisor-sidecar`: FAIL

判讀：

1. 這條基線代表 cluster 本身可用，`Istio control plane` 也能活
2. 但 `RuntimeClass gvisor` probe 沒有產出乾淨成功結果
3. `Istio + gVisor` workload 進一步卡在 `Init:Error`

## 1.34/1.34 結果

Stack: `k3s-gvisor-134`

執行項目：

1. `nodes-ready`
2. `baseline-pod`
3. `gvisor-runtime`

結果：

- `nodes-ready`: PASS
- `baseline-pod`: FAIL
- `gvisor-runtime`: FAIL

關鍵 failure：

- 一般 `baseline-pod` 與 `RuntimeClass gvisor` probe 都在 worker 上撞到 `FailedCreatePodSandBox`
- 底層錯誤是 `bandwidth` CNI plugin panic

這意味著 `1.34/1.34` 的問題已經不是純粹的 gVisor runtime probe，而是更早就傷到一般 workload compatibility。

## Decision Lab 判讀

這次結果代表：

1. `gVisor` 目前不能再標成 `NOT_TESTED`
2. `1.31/1.31` 是 `baseline OK, runtime path FAIL`
3. `1.34/1.34` 是 `baseline FAIL, runtime path FAIL`
4. 這條候選目前在 `Compatibility` 與 `Ops` 面向都明顯弱於 `OpenShell + CRI-O`

## Raw evidence

對應原始輸出位於：

- `records/raw/2026-06-12/k3s-gvisor-cilium/`
- `records/raw/2026-06-12/k3s-gvisor-134-cilium/`

主要檔案：

- `nodes-ready.json`
- `baseline-pod.json`
- `gvisor-runtime.json`
- `istio-control-plane.json`
- `istio-gvisor-sidecar.json`
