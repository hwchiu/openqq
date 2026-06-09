# Install Path: K3s + OpenShell + runc

這是目前最完整、最穩的 OpenShell 主線，底層已統一為 `K3s 1.31 + CRI-O 1.31`。

## 最短路徑

```bash
./scripts/install-k3s-openshell-runc.sh
```

## 06-09 最新實測狀態

- `nodes-ready`: PASS
- `baseline-pod`: PASS
- `istio-control-plane`: PASS
- `istio-sidecar-smoke`: PASS
- `openshell-control-plane`: PASS
- `openshell-guardrails`: PASS

## 判讀

這條路在 `1.31 + CRI-O 1.31` 重新驗證後，仍然是最穩的主線。

- OpenShell control plane 穩定
- guardrails 穩定
- Istio 一般 sidecar 不會把它打壞

## 參考報告

- [testing/comparison-matrix-live-2026-06-09.md](/Users/hwchiu/hwchiu/openqq/testing/comparison-matrix-live-2026-06-09.md)
- [testing/istio-impact-2026-06-09.md](/Users/hwchiu/hwchiu/openqq/testing/istio-impact-2026-06-09.md)
