# Initial Baseline Status - 2026-06-10

這份紀錄不是最終推薦報告，而是新 `Decision Lab` 模型建立後的第一份正式狀態摘要。

目的只有一個：

先確認目前還活著的 `K8s 1.31 + CRI-O 1.31` 四個 stack，是否至少通過最基本的 baseline 健康檢查，並把結果寫回 `docs/data/current-state.json` 與 GitHub Pages。

## 檢查範圍

針對目前存在的四個 stack：

1. `k3s-gvisor`
2. `k3s-openshell-runc`
3. `k3s-openshell-gvisor`
4. `k3s-kubearmor-runc`

執行的最小驗證包含：

1. `nodes-ready`
2. `baseline-pod`
3. `istio-control-plane`
4. `openshell-control-plane` for OpenShell stacks only

## 結果摘要

### `k3s-gvisor`

- `nodes-ready`: PASS
- `baseline-pod`: PASS
- `istio-control-plane`: PASS

判讀：

- 目前至少可確認 cluster baseline 與 Istio control plane 是活的
- 這不等於 gVisor 專屬 scenario 已經過關

### `k3s-openshell-runc`

- `nodes-ready`: PASS
- `baseline-pod`: PASS
- `istio-control-plane`: PASS
- `openshell-control-plane`: PASS

判讀：

- 這是目前最接近主推薦路線的候選
- 但正式 recommendation 仍要等 scenario 家族重跑後才能定案

### `k3s-openshell-gvisor`

- `nodes-ready`: PASS
- `baseline-pod`: PASS
- `istio-control-plane`: PASS
- `openshell-control-plane`: PASS

判讀：

- 複合路線目前至少沒有死在 baseline 與 control plane
- 但 protection / compatibility / ops 的正式評估仍未完成

### `k3s-kubearmor-runc`

- `nodes-ready`: PASS
- `baseline-pod`: PASS
- `istio-control-plane`: PASS

判讀：

- 目前只證明 baseline 與 Istio control plane 存活
- KubeArmor 在這個 repo 裡未來要用 explicit policy 重跑，不再用 default behavior 判斷成功

## Raw archive

對應原始輸出位於：

- `records/raw/2026-06-10/initial-current-state/`

## 對 current-state 的影響

這次更新後，`docs/data/current-state.json` 已將：

- `OpenShell + CRI-O`
- `gVisor`
- `OpenShell + gVisor`
- `KubeArmor`
- `Istio 視角`

在 `K8s 1.31 + CRI-O 1.31` 上的狀態，從純占位改成基於實測的初步狀態。

## 尚未完成

這份紀錄沒有完成以下事項：

- `K8s 1.34 + CRI-O 1.34`
- `k8s + cri-o` 對照組
- scenario 家族正式重跑
- allowed / blocked pair 驗證
- KubeArmor explicit-policy 評估
- 最終 recommendation 定案
