# Install Path: K3s + gVisor

這條路線只建立 `K3s 1.31 + CRI-O 1.31 + gVisor`，不安裝 OpenShell。

先講清楚：

- 這條路在 `2026-06-09` 的 live rerun 中，**叢集有建立成功**
- 但 bare `RuntimeClass gvisor` probe 是 `FAIL`
- 所以目前 repo **不能宣稱** `K3s 1.31 + CRI-O 1.31 + gVisor` 已被完整證明成功

如果你要看「哪個版本真的被證明跑起來」與「哪個版本目前沒有」，先看：

- [docs/runbooks/gvisor-version-proof.md](/Users/hwchiu/hwchiu/openqq/docs/runbooks/gvisor-version-proof.md)

## 最短路徑

```bash
./scripts/install-k3s-gvisor.sh
```

## 它會做什麼

1. 套用 `terraform/stacks/k3s-gvisor`
2. 啟動三節點叢集
3. 安裝 `runsc` 並配置 CRI-O runtime handler
4. 抓回 kubeconfig 到 `generated/stacks/k3s-gvisor/kubeconfig`
5. 驗證節點 `Ready`
6. 嘗試驗證 `RuntimeClass/gvisor`

## 06-09 最新實測狀態

- `nodes-ready`: PASS
- `baseline-pod`: PASS
- `istio-control-plane`: PASS
- `istio-sidecar-smoke`: PASS
- `gvisor-runtime`: FAIL
- `istio-gvisor-sidecar`: FAIL

這代表：
- 叢集基線與一般 workload 沒問題
- 但 bare `RuntimeClass gvisor` workload 仍沒有乾淨成功結果
- 疊上 Istio sidecar 後也沒有變好

## 這條路現在能證明什麼

可以證明：

1. `K3s v1.31.14+k3s1`
2. `CRI-O 1.31.13`
3. `runsc` 安裝流程與 `RuntimeClass/gvisor` 建立流程都已執行
4. 一般非 gVisor workload 正常

不能證明：

1. bare `RuntimeClass gvisor` workload 已穩定成功
2. `Istio + RuntimeClass gvisor` 已可用

## 參考報告

- [testing/comparison-matrix-live-2026-06-09.md](/Users/hwchiu/hwchiu/openqq/testing/comparison-matrix-live-2026-06-09.md)
- [testing/istio-impact-2026-06-09.md](/Users/hwchiu/hwchiu/openqq/testing/istio-impact-2026-06-09.md)
- [docs/runbooks/gvisor-version-proof.md](/Users/hwchiu/hwchiu/openqq/docs/runbooks/gvisor-version-proof.md)
