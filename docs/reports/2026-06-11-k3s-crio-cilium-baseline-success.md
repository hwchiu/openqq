# K3s + CRI-O + Cilium Baseline Success - 2026-06-11

這份紀錄對應 `k3s-crio` 在 `K8s 1.31 + CRI-O 1.31` 上，改用正式 `Cilium` baseline 後的第一次完整 live success。

它不是延續舊的 `Flannel workaround`，而是針對新的正式比較模型：

- `K3s --flannel-backend=none`
- `CRI-O`
- `Cilium`

## 測試基線

- `K8s 1.31 + CRI-O 1.31`
- Stack: `k3s-crio`

## 這次驗證的重點

1. `3 nodes` 是否都能在 `no-flannel` 模式下成功註冊
2. `Cilium` 是否能成功接手 CNI，讓節點轉成 `Ready`
3. baseline workload 是否可執行
4. `Istio control plane` 是否能在這條 baseline 上正常啟動

## 執行項目

1. `nodes-ready`
2. `baseline-pod`
3. `istio-control-plane`

## 結果

- `nodes-ready`: PASS
- `baseline-pod`: PASS
- `istio-control-plane`: PASS

## 關鍵修正

這次成功建立在兩個 live-debug 修正之上：

1. `--flannel-backend=none` 只能放在 `k3s server`，不能傳給 `k3s agent`
2. `no-flannel` 模式下，workflow 必須改成：
   - `wait_for_node_count`
   - `install cilium`
   - `wait_for_nodes_ready`

如果先等 `nodes Ready` 才裝 Cilium，整個 cluster 會卡在 `NetworkPluginNotReady`。

## Decision Lab 判讀

這次結果代表：

1. `K3s + CRI-O + Cilium` 在 `1.31/1.31` 上已經不是設計假說，而是實際可用基線
2. plain CRI-O 的 `baseline` 與 `Istio control plane` 已在新正式 CNI baseline 上成立
3. 後續 `OpenShell`、`gVisor`、`KubeArmor` 可以建立在這條已證明的 baseline 上重跑

## Raw evidence

對應原始輸出位於：

- `records/raw/2026-06-10/k3s-crio-cilium-131/`

主要檔案：

- `nodes-ready.json`
- `baseline-pod.json`
- `istio-control-plane.json`
- `nodes-wide.txt`
- `kube-system-pods.txt`
