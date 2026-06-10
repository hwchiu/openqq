# K3s + CRI-O Baseline Recovery - 2026-06-10

這份紀錄對應 `k3s-crio` 在 `K8s 1.31 + CRI-O 1.31` 基線上的 follow-up live rerun。

它延續 [2026-06-10-k3s-crio-baseline-failure.md](./2026-06-10-k3s-crio-baseline-failure.md)，目的不是洗掉第一次失敗，而是確認先前的 `bandwidth` panic 到底是 solution 不支援，還是可修正的 configuration regression。

## 測試基線

- `K8s 1.31 + CRI-O 1.31`
- Stack: `k3s-crio`

## 這次修正

- 保持 `/opt/cni/bin` 指向 `/usr/lib/cni/*`
- 以 pinned `10-flannel.conflist` 覆寫成 `flannel + portmap`
- 移除先前會讓 `bandwidth` plugin 進入 `cmdCheck` panic 的 stanza

這次 follow-up 是直接對現存 Azure stack 套用與 repo / IaC 同步的 flannel override 後重跑。

## 執行項目

1. `nodes-wide`
2. `baseline-pod`

## 結果

- `nodes-wide`: PASS
- `baseline-pod`: PASS

## Recovery 特徵

這次已不再重現第一次 failure report 的系統性症狀：

- 三個節點皆維持 `Ready`
- baseline smoke pod 可以完成
- pod log 回到 `matrix-smoke-ok`

這代表 plain CRI-O 至少已恢復到可承載 baseline workload 的狀態。

## Decision Lab 判讀

這次結果代表：

1. 舊的 plain-CRI-O FAIL 不應再被解讀成「本質不支援」
2. 這次 recovery 證明先前根因屬於 flannel CNI configuration regression
3. `plain CRI-O` 目前應更新成 `baseline smoke recovered, full rerun pending`
4. `istio-control-plane` 與後續 scenario 仍需在修正後基線上重跑

## Raw evidence

對應原始輸出位於：

- `records/raw/2026-06-10/k3s-crio-smoke-recovery/`

主要檔案：

- `baseline-pod.json`
- `nodes-wide.txt`
- `cni-override.txt`
