# K3s + CRI-O 1.34 Baseline Recovery - 2026-06-10

這份紀錄對應 `k3s-crio-134` 在 `K8s 1.34 + CRI-O 1.34` 基線上的 follow-up live rerun。

它延續 [2026-06-10-k3s-crio-134-baseline-failure.md](./2026-06-10-k3s-crio-134-baseline-failure.md)，目的是確認先前跨到 `1.34/1.34` 之後看到的 failure，是不是同樣來自可修正的 flannel CNI configuration regression。

## 測試基線

- `K8s 1.34 + CRI-O 1.34`
- Stack: `k3s-crio-134`

## 版本確認

這次 follow-up 使用的 live stack 版本仍是：

- `v1.34.1+k3s1`
- `cri-o://1.34.9`

## 這次修正

- 保持 `/opt/cni/bin` 指向 `/usr/lib/cni/*`
- 以 pinned `10-flannel.conflist` 覆寫成 `flannel + portmap`
- 移除先前會讓 `bandwidth` plugin 進入 `cmdCheck` panic 的 stanza

這次 follow-up 同樣是直接對現存 Azure stack 套用與 repo / IaC 同步的 flannel override 後重跑。

## 執行項目

1. `nodes-wide`
2. `baseline-pod`

## 結果

- `nodes-wide`: PASS
- `baseline-pod`: PASS

## Recovery 特徵

這次已不再重現第一次 failure report 的 `ContainerCreating` 大量堆積：

- 三個節點皆維持 `Ready`
- baseline smoke pod 可以完成
- pod log 回到 `matrix-smoke-ok`

這表示 `1.34/1.34` 的 plain CRI-O 至少已恢復到可承載 baseline workload 的狀態，不應再直接沿用第一次 failure report 的總結。

## Decision Lab 判讀

這次結果代表：

1. `1.34/1.34` 上的 plain CRI-O 不能再直接標成 `FAIL`
2. 舊的 bandwidth panic 目前應視為可修正的 flannel CNI configuration regression
3. `plain CRI-O` 目前應更新成 `baseline smoke recovered, full rerun pending`
4. `istio-control-plane`、`gVisor`、`OpenShell` 等 1.34 scenario 仍需在修正後基線上重跑

## Raw evidence

對應原始輸出位於：

- `records/raw/2026-06-10/k3s-crio-134-smoke-recovery/`

主要檔案：

- `baseline-pod.json`
- `nodes-wide.txt`
- `cni-override.txt`
