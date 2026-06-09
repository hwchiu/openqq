# Install Path: K3s + OpenShell + gVisor

這條路線驗證 OpenShell 在 `K3s 1.31 + CRI-O 1.31 + runsc` 路徑上，哪些能力保留、哪些邊界還沒打通。

## 最短路徑

```bash
./scripts/install-k3s-openshell-gvisor.sh
```

## 06-09 最新實測狀態

- `nodes-ready`: PASS
- `baseline-pod`: PASS
- `istio-control-plane`: PASS
- `istio-sidecar-smoke`: PASS
- `gvisor-runtime`: FAIL
- `istio-gvisor-sidecar`: FAIL
- `openshell-control-plane`: PASS
- `openshell-guardrails`: PASS

## 判讀

這條路線現在不能再簡單寫成「degraded」。正確說法是：

1. bare `RuntimeClass gvisor` workload 還不穩
2. `Istio + gVisor sidecar` workload 不可用
3. 但 `OpenShell` 自己的 control plane 與 guardrails 在這輪是 `PASS`

## 參考報告

- [testing/comparison-matrix-live-2026-06-09.md](/Users/hwchiu/hwchiu/openqq/testing/comparison-matrix-live-2026-06-09.md)
- [testing/istio-impact-2026-06-09.md](/Users/hwchiu/hwchiu/openqq/testing/istio-impact-2026-06-09.md)
