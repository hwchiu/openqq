# Install Path: K3s + gVisor

這條路線只建立 `K3s 1.31 + CRI-O 1.31 + gVisor`，不安裝 OpenShell。

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

## 參考報告

- [testing/comparison-matrix-live-2026-06-09.md](/Users/hwchiu/hwchiu/openqq/testing/comparison-matrix-live-2026-06-09.md)
- [testing/istio-impact-2026-06-09.md](/Users/hwchiu/hwchiu/openqq/testing/istio-impact-2026-06-09.md)
