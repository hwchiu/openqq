# K3s + CRI-O 1.34 Baseline Failure - 2026-06-10

> Update 2026-06-10: 之後的 follow-up live rerun 已在 pinned flannel CNI config 下恢復 `baseline-pod`。這份文件保留第一次 failure observation；目前結論請同時參考 [2026-06-10-k3s-crio-134-baseline-recovery.md](./2026-06-10-k3s-crio-134-baseline-recovery.md)。

這份紀錄對應 `k3s-crio-134`，也就是 plain CRI-O 對照組在 `K8s 1.34 + CRI-O 1.34` 基線上的第一次正式重跑。

這次重跑先修正了一個 IaC 問題：原本 `-134` stack 缺少實際 `stack.auto.tfvars`，第一次部署錯用了 `1.31/1.31` 預設值，因此那次結果無效。修正後重新建立，節點版本已確認是：

- `v1.34.1+k3s1`
- `cri-o://1.34.9`

## 測試基線

- `K8s 1.34 + CRI-O 1.34`
- Stack: `k3s-crio-134`

## 執行項目

1. `nodes-ready`
2. `baseline-pod`
3. `istio-control-plane`

## 結果

- `nodes-ready`: PASS
- `baseline-pod`: FAIL
- `istio-control-plane`: FAIL

## 失敗特徵

這次和 `1.31/1.31` 對照組出現了相同形態的問題：

- 三個節點都能註冊並進入 `Ready`
- 但一般 workload 與 `kube-system` pod 仍卡在 `ContainerCreating`
- `coredns`、`metrics-server`、`helm-install-traefik*` 都無法順利建立 sandbox
- `istiod` 因前置元件異常而無法進入 ready

這代表 `nodes Ready` 仍然不能被視為 solution 成功。

## 直接原因

cluster events、`baseline-pod` describe 與 control plane `k3s` journal 都指向同一個問題：

- CNI `bandwidth` plugin 在 `error checking pod ... for CNI network "cbr0"` 路徑上 panic
- 結果是 `FailedCreatePodSandBox`

這不是 `1.31/1.31` 的單次偶發，而是 plain CRI-O 對照組在 `1.34/1.34` 上也重現的系統性失敗。

## Decision Lab 判讀

這次結果代表：

1. `plain CRI-O` 在兩條正式基線上都已經出現相同型態的 workload failure
2. `K8s 1.34 + CRI-O 1.34` 目前也應標記為 `FAIL`
3. 失敗性質仍主要落在 `Compatibility`
4. 根因跨基線一致，也會進一步拖累 `Operational Complexity`

現在不能再把 plain CRI-O 視為「只是尚未補測的中性對照組」。

## Raw evidence

對應原始輸出位於：

- `records/raw/2026-06-10/k3s-crio-134-smoke/`

主要檔案：

- `nodes-ready.json`
- `baseline-pod.json`
- `istio-control-plane.json`
- `pods-wide.txt`
- `events.txt`
- `control-plane-k3s-journal.txt`

## 下一步

1. 對 `OpenShell + CRI-O`、`gVisor`、`OpenShell + gVisor`、`KubeArmor` 補跑 `1.34/1.34`
2. 確認 plain CRI-O 的失敗是否能被額外 policy / runtime layer 緩解
3. 把跨基線一致的 failure 更新回 `docs/data/current-state.json` 與 GitHub Pages
