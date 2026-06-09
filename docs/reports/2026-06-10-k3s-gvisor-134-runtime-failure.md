# K3s + gVisor 1.34 Runtime Verification Failure - 2026-06-10

這份紀錄對應 `k3s-gvisor-134`，也就是 `gVisor` 候選在 `K8s 1.34 + CRI-O 1.34` 基線上的第一次正式重跑。

## 測試基線

- `K8s 1.34 + CRI-O 1.34`
- Stack: `k3s-gvisor-134`

## 執行項目

1. Terraform 建立基礎叢集
2. `nodes-ready`
3. 安裝 `runsc`
4. 建立 `RuntimeClass gvisor`
5. 執行 `gvisor-verify` probe pod

## 結果

- Terraform apply: PASS
- `nodes-ready`: PASS
- `runsc` 安裝: PASS
- `RuntimeClass gvisor` 建立: PASS
- `gvisor-verify` probe pod: FAIL

## 失敗特徵

這次和 plain CRI-O / OpenShell + CRI-O 不同，control plane workload 有更高完成度：

- `coredns`、`metrics-server`、`local-path-provisioner` 能正常 `Running`
- `helm-install-traefik*` 能完成

但 `gVisor` 驗證 pod 在 worker 上仍卡在 `ContainerCreating`，而且部分 worker-side pod 也有相同行為：

- `gvisor-verify-*`
- `svclb-traefik-*` 的 worker 副本
- `traefik` worker pod

## 直接原因

手動保留的 `gvisor` probe describe、events 與 control plane journal 都指向同一個根因：

- CNI `bandwidth` plugin 在 `error checking pod ... for CNI network "cbr0"` 路徑上 panic
- 結果是 `FailedCreatePodSandBox`

這表示：

- 叢集不是整體不可用
- 但 `gVisor` 候選在需要 worker-side sandbox 的實際驗證上仍失敗

## Decision Lab 判讀

這次結果代表：

1. `gVisor` 在 `1.34/1.34` 上不能標成 `NOT_TESTED`
2. 它應先標成 `FAIL`
3. 失敗性質主要落在：
   - `Compatibility`
   - `Operational Complexity`

因為它雖然完成了比 plain CRI-O 更多的 bootstrap 步驟，但真正需要 `RuntimeClass gvisor` 的 workload 仍無法成功建立 sandbox。

## Raw evidence

對應原始輸出位於：

- `records/raw/2026-06-10/k3s-gvisor-134-runtime-verify/`

主要檔案：

- `nodes-ready.json`
- `pods-wide.txt`
- `events.txt`
- `runtimeclass-gvisor.yaml`
- `gvisor-manual-pod.txt`
- `control-plane-k3s-journal.txt`

## 下一步

1. 繼續驗證 `OpenShell + gVisor` 與 `KubeArmor` 在 `1.34/1.34` 上的狀態
2. 確認 worker-side sandbox failure 是否仍然是相同 CNI bug 的變體
3. 把這次結果正式寫回 current-state 與 GitHub Pages
