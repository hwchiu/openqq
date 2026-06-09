# Install Path: K3s + KubeArmor + runc

這條路線是 OpenShell 之外的獨立 runtime security 對照線，底層已統一為 `K3s 1.31 + CRI-O 1.31`。

## 最短路徑

```bash
./scripts/install-k3s-kubearmor-runc.sh
```

## 06-09 最新實測狀態

- `nodes-ready`: PASS
- `baseline-pod`: PASS
- `istio-control-plane`: PASS
- `istio-sidecar-smoke`: PASS
- `kubearmor-sa-block`: PASS
- `kubearmor-file-block`: PASS
- `kubearmor-process-block`: FAIL
- `kubearmor-network-block`: FAIL

## 判讀

KubeArmor 這輪不是全好，也不是全壞。

- `service account token` 能擋
- sensitive file read 能擋
- process execution 還沒擋住
- curl TCP egress 還沒擋住

所以它目前比較像：
- 對 secret/file 類保護有明確效果
- 對更完整的 agentic runtime 約束還不夠

## 參考報告

- [testing/comparison-matrix-live-2026-06-09.md](/Users/hwchiu/hwchiu/openqq/testing/comparison-matrix-live-2026-06-09.md)
- [testing/kubearmor-agentic-scenarios-2026-06-08.md](/Users/hwchiu/hwchiu/openqq/testing/kubearmor-agentic-scenarios-2026-06-08.md)
- [testing/modelarmor-lab-validation-2026-06-08.md](/Users/hwchiu/hwchiu/openqq/testing/modelarmor-lab-validation-2026-06-08.md)
