# Install Path: Four-Way Comparison Matrix

這條路線會一次建立四套獨立環境，基線統一為：

- `K3s v1.31.14+k3s1`
- `CRI-O 1.31.13`
- `Ubuntu 22.04`

## 四套環境

1. `k3s-gvisor`
2. `k3s-openshell-runc`
3. `k3s-openshell-gvisor`
4. `k3s-kubearmor-runc`

## 一鍵建立

```bash
./scripts/install-comparison-matrix.sh
```

## 06-09 live rerun 結果摘要

- 四套叢集都成功建立
- 四套節點都 `Ready`
- 四套都能裝上 `Istio 1.30.1`
- `OpenShell + runc`: 完整通過
- `OpenShell + gVisor`: OpenShell 路徑通過，但 bare gVisor probe / gVisor sidecar 失敗
- `KubeArmor + runc`: file/secret 類保護有效，process/network 失敗

主報告：
- [testing/comparison-matrix-live-2026-06-09.md](/Users/hwchiu/hwchiu/openqq/testing/comparison-matrix-live-2026-06-09.md)

## 清理

```bash
./scripts/destroy-comparison-matrix.sh
```
