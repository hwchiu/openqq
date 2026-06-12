# K3s + CRI-O + KubeArmor 1.34 Policy Results - 2026-06-12

這份紀錄對應 `k3s-kubearmor-runc-134` 在 `K8s 1.34 + CRI-O 1.34` 上，建立在正式 `Cilium` baseline 之上的 explicit-policy 驗證。

這次的重點不是看 default behavior，而是看明確 policy 能不能精準命中不同 scenario。

## 測試基線

- `K8s 1.34 + CRI-O 1.34`
- Stack: `k3s-kubearmor-runc-134`

## 執行項目

1. `nodes-ready`
2. `baseline-pod`
3. `kubearmor-file-block`
4. `kubearmor-network-block`
5. `kubearmor-process-block`
6. `kubearmor-sa-block`
7. `istio-control-plane`
8. `istio-sidecar-smoke`

## 結果

- `nodes-ready`: PASS
- `baseline-pod`: PASS
- `kubearmor-file-block`: PASS
- `kubearmor-network-block`: FAIL
- `kubearmor-process-block`: FAIL
- `kubearmor-sa-block`: PASS
- `istio-control-plane`: PASS
- `istio-sidecar-smoke`: PASS

## 判讀

這次結果代表：

1. `KubeArmor` 在 `1.34/1.34` 上也能穩定提供 `file` 與 `service account token` 兩類 protection
2. 同一輪 explicit-policy 下，`network` 與 `process execution` 仍然沒有成功擋住
3. `Istio` 與一般 workload 仍可正常運作，所以這條候選不是靠破壞 compatibility 來換 protection
4. `1.31` 與 `1.34` 兩條 baseline 的結果現在已經收斂成同一個判讀：這條候選目前應該被判成 `partial`

## Raw evidence

對應原始輸出位於：

- `records/raw/2026-06-12/k3s-kubearmor-runc-134-cilium/`

主要檔案：

- `nodes-ready.json`
- `baseline-pod.json`
- `kubearmor-file-block.json`
- `kubearmor-network-block.json`
- `kubearmor-process-block.json`
- `kubearmor-sa-block.json`
- `istio-control-plane.json`
- `istio-sidecar-smoke.json`
