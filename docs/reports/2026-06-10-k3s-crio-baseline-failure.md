# K3s + CRI-O Baseline Failure - 2026-06-10

> Update 2026-06-10: 之後的 follow-up live rerun 已在 pinned flannel CNI config 下恢復 `baseline-pod`。這份文件保留第一次 failure observation；目前結論請同時參考 [2026-06-10-k3s-crio-baseline-recovery.md](./2026-06-10-k3s-crio-baseline-recovery.md)。

這份紀錄對應 `k3s-crio`，也就是沒有額外 sandbox / policy layer 的 plain CRI-O 對照組。

目的不是證明這條路線最終一定不適合，而是把它在新 `Decision Lab` 模型下第一次正式重跑的結果寫成可閱讀記錄。

## 測試基線

- `K8s 1.31 + CRI-O 1.31`
- Stack: `k3s-crio`

## 執行項目

1. `nodes-ready`
2. `baseline-pod`
3. `istio-control-plane`

## 結果

- `nodes-ready`: PASS
- `baseline-pod`: FAIL
- `istio-control-plane`: FAIL

## 失敗特徵

表面上 cluster 不是完全起不來：

- `cp-0`
- `worker-1`
- `worker-2`

三個節點都能註冊並進入 `Ready`。

但這不代表 baseline 成功。實際 workload 與 kube-system pod 在建立 sandbox 時失敗，導致：

- `baseline-pod` 無法完成
- `coredns` 無法正常起來
- `metrics-server` 無法正常起來
- `helm-install-traefik` / `helm-install-traefik-crd` 無法完成
- `istiod` 無法進入 ready

## 直接原因

control plane `k3s` journal 與 cluster events 都指向同一個問題：

- CNI `bandwidth` plugin 在 `error checking pod ... for CNI network "cbr0"` 路徑上 panic
- 結果是 `FailedCreatePodSandBox`

這不是單一業務 pod 的偶發錯誤，而是會影響 baseline workload 與 service mesh control plane 的系統性問題。

## Decision Lab 判讀

這次結果代表：

1. `plain CRI-O` 不能再被標成 `NOT_TESTED`
2. 在 `K8s 1.31 + CRI-O 1.31` 上，它目前應視為 `FAIL`
3. 失敗性質主要落在 `Compatibility`
4. 這個結果也會拖累 `Operational Complexity`

原因是：

- 即使節點 Ready，實際 workload 仍無法正常建立 sandbox
- 要把這種 CNI / runtime 交界問題查清楚，本身就是維運成本

## Raw evidence

對應原始輸出位於：

- `records/raw/2026-06-10/k3s-crio-smoke/`

主要檔案：

- `nodes-ready.json`
- `baseline-pod.json`
- `istio-control-plane.json`
- `pods-wide.txt`
- `events.txt`
- `control-plane-k3s-journal.txt`

## 下一步

1. 重跑 `K8s 1.34 + CRI-O 1.34` plain 對照組
2. 確認這個 CNI panic 是 `1.31/1.31` 特有問題，還是 plain CRI-O 路線普遍問題
3. 把結果繼續寫回 `docs/data/current-state.json` 與 GitHub Pages
