# K3s + gVisor 1.35 Spike - 2026-06-13

這份紀錄對應 `k3s-gvisor-135`，也就是把 `K8s + gVisor` 這條戰線暫時拉到 `K8s 1.35 + CRI-O 1.35`，確認它是不是只差版本門檻就能跨過目前的 compatibility 問題。

這不是新的正式 baseline，也不會取代 repo 目前的官方比較基線：

- `K8s 1.31 + CRI-O 1.31`
- `K8s 1.34 + CRI-O 1.34`

它是一條獨立 spike，用來回答一個更窄的問題：

1. `1.35` 能不能讓 `gVisor` 擺脫 `1.34` 那類明顯失敗
2. 問題到底是 repo wiring，還是 `CRI-O` 與 `runsc` 的整合邊界

## 測試組合

- Stack: `k3s-gvisor-135`
- `K3s v1.35.5+k3s1`
- `CRI-O 1.35.4`
- `runsc release-20260608.0`
- `K3s --flannel-backend=none`
- `Cilium`

## Live 結果

### Platform baseline

- `terraform apply`: PASS
- `3 nodes registered`: PASS
- `Cilium install`: PASS
- `nodes-ready`: PASS

這表示 `1.35` 的 plain platform baseline 本身是健康的，至少沒有重現先前 `1.34` 那種一般 workload 先被打壞的狀態。

### Current repo wiring: `runtime_type = "oci" + runtime_path = /usr/bin/runsc`

短生命週期 verify pod：

- pod sandbox 建立: PASS
- image pull: PASS
- container create: PASS
- `StartContainer`: PASS
- Kubernetes workload completion: FAIL

關鍵觀察：

1. `kubectl describe pod` 顯示 verify pod 確實被排到 `cp-0`，container 也確實被 `Created` / `Started`
2. `runsc list` 顯示 sandbox 與 container 都存在，而且 verify pod 對應 workload 已經 `stopped`
3. `crio` journal 持續重複：
   - `Failed to find container exit file`
4. Kubernetes 視角最後看到的是：
   - `Exit Code: -1`
   - 不合理的 `FinishedAt` 時間

這表示 `runsc` 不是完全沒跑，而是 workload 已經跑完了，但 `CRI-O` 沒有把 exit / status 同步乾淨地回報給 kubelet。

### Long-running pod 實驗

為了排除「只是短生命週期 probe 太快退出」這個假設，另外建立了 `sleep 300` 的 gVisor pod。

結果：

1. `runsc list` 顯示 sandbox 與 container 都是 `running`
2. `crictl inspect` 顯示 PID 存在，但 state 仍停在 `CONTAINER_CREATED`
3. Kubernetes 視角維持 `ContainerCreating`

這代表問題不只是短命 probe；就算 workload 持續存活，`CRI-O 1.35` 也仍然沒有把 runsc workload 正確提升到 kubelet 可用的 `RUNNING` 狀態。

### Alternative path: `runtime_type = "vm" + containerd-shim-runsc-v1`

另外做了一次更接近 gVisor 新文件方向的分支測試，只在 `cp-0` 改成：

- `runtime_type = "vm"`
- `runtime_path = "/usr/bin/containerd-shim-runsc-v1"`

結果比 `oci` 路徑更差：

1. `crio` restart 無法乾淨恢復
2. `cp-0` 進入 `NotReady`
3. kube-apiserver 對外連線一度直接拒絕

因此這條路在 `1.35` 上不能視為可行修正。

## Decision Lab 判讀

這次 spike 的價值不是把 `gVisor` 判成 PASS，而是把根因縮得更清楚：

1. `1.35` 明顯比 `1.34` 前進
   - workload 已能進到 `runsc` 真正執行
2. 但它仍然不是 Kubernetes compatibility PASS
   - 因為 kubelet / CRI-O 看不到乾淨的 workload lifecycle state
3. `vm + shim` 在 `1.35` 上不是現成解法
4. 所以目前最合理的判讀是：
   - `1.35` 緩解了症狀
   - 但沒有跨過 repo 所需的可用門檻

## 結論

這份 spike 支持一個很具體的說法：

`gVisor` 目前的問題不只是 repo 腳本寫壞，也不只是 `1.34` 太舊；就算拉到 `CRI-O 1.35`，在目前這條整合路徑上，`runsc` 與 `CRI-O` 的狀態同步仍然不夠完整。

如果之後要再往前追，最有價值的方向會是：

1. 直接驗更高版本的 `CRI-O`
2. 對照 gVisor 新的 `CRI-O` 支援路線是否真的要求更高版本門檻

## Raw evidence

- `records/raw/2026-06-13/k3s-gvisor-135-spike/`
