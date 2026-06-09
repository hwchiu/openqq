# K3s + OpenShell + CRI-O 1.34 Bootstrap Blocked - 2026-06-10

這份紀錄對應 `k3s-openshell-runc-134`，也就是 `OpenShell + CRI-O` 在 `K8s 1.34 + CRI-O 1.34` 基線上的第一次正式重跑。

## 測試基線

- `K8s 1.34 + CRI-O 1.34`
- Stack: `k3s-openshell-runc-134`

## 執行項目

1. Terraform 建立基礎叢集
2. `nodes-ready`
3. `agent-sandbox-controller` 安裝與 rollout
4. OpenShell stack 安裝前置流程

## 結果

- Terraform apply: PASS
- `nodes-ready`: PASS
- `agent-sandbox-controller rollout`: FAIL
- OpenShell 後續驗證：BLOCKED

## 失敗特徵

這次不是叢集完全起不來：

- 三個節點都能進入 `Ready`
- 版本已確認是 `v1.34.1+k3s1` + `cri-o://1.34.9`

但在安裝 OpenShell 前置控制面時，`agent-sandbox-controller` deployment 無法 rollout，最後以 timeout 結束。

同時間 `kube-system` 與 `agent-sandbox-system` 的 pod 都卡在 `ContainerCreating`：

- `agent-sandbox-controller`
- `coredns`
- `metrics-server`
- `local-path-provisioner`
- `helm-install-traefik*`

## 直接原因

cluster events 與 control plane `k3s` journal 顯示，根因仍是：

- CNI `bandwidth` plugin 在 `error checking pod ... for CNI network "cbr0"` 路徑上 panic
- 結果是 `FailedCreatePodSandBox`

也就是說，這次不是 OpenShell policy 或 controller 邏輯本身先出問題，而是底層 workload sandbox 先失敗，導致 OpenShell bootstrap 被阻塞。

## Decision Lab 判讀

這次結果應該被記為：

1. `OpenShell + CRI-O` 在 `1.34/1.34` 上目前是 `BLOCKED`
2. 阻塞原因是 `install/bootstrap blocked by underlying workload failure`
3. 這個結果同時影響：
   - `Compatibility`
   - `Operational Complexity`

重要的是，這不該被寫成 `NOT_TESTED`。因為我們確實跑了，而且 solution 在正式 bootstrap 流程中遇到有效失敗。

## Raw evidence

對應原始輸出位於：

- `records/raw/2026-06-10/k3s-openshell-runc-134-bootstrap/`

主要檔案：

- `nodes-ready.json`
- `pods-wide.txt`
- `events.txt`
- `agent-sandbox-controller-deploy.txt`
- `control-plane-k3s-journal.txt`

## 下一步

1. 繼續測 `gVisor`、`OpenShell + gVisor`、`KubeArmor` 在 `1.34/1.34` 上的行為
2. 釐清這個跨 stack 重現的 CNI panic 是否是 plain CRI-O / CRI-O family 共通問題
3. 把 `OpenShell + CRI-O` 的 `1.34/1.34` 狀態正式寫回 current-state 與 Pages
