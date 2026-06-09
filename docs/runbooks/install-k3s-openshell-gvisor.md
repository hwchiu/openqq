# Install Path: K3s + OpenShell + gVisor

這條路線驗證 OpenShell 在 `K3s 1.31 + CRI-O 1.31 + runsc` 路徑上，哪些能力保留、哪些邊界還沒打通。

先講清楚：

- `OpenShell + gVisor` 在 `2026-06-09` 這輪是 `PASS`
- 但 bare `RuntimeClass gvisor` probe 同一輪仍是 `FAIL`
- 所以不能把這條路寫成「`CRI-O 1.31` 上的 bare gVisor 已被證明成功」

這條線比較精確的說法是：

- `OpenShell sandbox path on gVisor + CRI-O 1.31`: 可用
- bare `RuntimeClass gvisor` on `CRI-O 1.31`: 尚未被這個 repo 證明成功

詳細版本與證據鏈：

- [docs/runbooks/gvisor-version-proof.md](/Users/hwchiu/hwchiu/openqq/docs/runbooks/gvisor-version-proof.md)

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
- [docs/runbooks/gvisor-version-proof.md](/Users/hwchiu/hwchiu/openqq/docs/runbooks/gvisor-version-proof.md)
