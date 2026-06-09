# Comparison Matrix Live Rerun - 2026-06-09

這份報告記錄四套 Azure lab 在 `K3s v1.31.14+k3s1 + CRI-O 1.31.13` 基線上的重新部署與 live rerun 結果。

先講清楚：

- 這份報告可以證明四套叢集都已在這個版本基線上重建
- 但它**不能**證明 bare `RuntimeClass gvisor` 已在這個版本基線上乾淨成功
- 如果你要看版本與證據鏈，請直接看：
  - [docs/runbooks/gvisor-version-proof.md](/Users/hwchiu/hwchiu/openqq/docs/runbooks/gvisor-version-proof.md)

## 基線

- Kubernetes: `v1.31.14+k3s1`
- Container runtime: `cri-o://1.31.13`
- Istio: `1.30.1`
- 驗證時間: `2026-06-09T13:07:54Z`
- 原始結果: [testing/raw/comparison-matrix-live-2026-06-09/summary.json](/Users/hwchiu/hwchiu/openqq/testing/raw/comparison-matrix-live-2026-06-09/summary.json)
- 失敗案例總整: [testing/failure-catalog-2026-06-09.md](/Users/hwchiu/hwchiu/openqq/testing/failure-catalog-2026-06-09.md)

## 四套環境結果總表

| 環境 | 節點 Ready | Baseline Pod | Istio Control Plane | Istio Sidecar Smoke | gVisor Runtime | Istio + gVisor Sidecar | OpenShell Control Plane | OpenShell Guardrails | KubeArmor SA | KubeArmor Process | KubeArmor File | KubeArmor Network |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `k3s-gvisor` | PASS | PASS | PASS | PASS | FAIL | FAIL | N/A | N/A | N/A | N/A | N/A | N/A |
| `k3s-openshell-runc` | PASS | PASS | PASS | PASS | N/A | N/A | PASS | PASS | N/A | N/A | N/A | N/A |
| `k3s-openshell-gvisor` | PASS | PASS | PASS | PASS | FAIL | FAIL | PASS | PASS | N/A | N/A | N/A | N/A |
| `k3s-kubearmor-runc` | PASS | PASS | PASS | PASS | N/A | N/A | N/A | N/A | PASS | FAIL | PASS | FAIL |

## 主要結論

1. 四套叢集都已成功升級到 `1.31 + CRI-O 1.31` 的叢集基線。
2. 四套叢集都能安裝 `Istio 1.30.1`，且一般 sidecar injection smoke test 都通過。
3. `RuntimeClass gvisor` 的直接 probe 在兩個 gVisor 路線都沒有得到乾淨成功結果，狀態是 `FAIL`。
4. `Istio + RuntimeClass gvisor` workload 在兩個 gVisor 路線都無法 ready，狀態是 `FAIL`。
5. `OpenShell + runc` 在這輪仍是完整主線，control plane 與 guardrails 都是 `PASS`。
6. `OpenShell + gVisor` 在這輪的 OpenShell guardrails 也通過，代表 OpenShell sandbox 路徑在目前 patcher / CRI-O 路線下可工作；但這不等於裸 `gvisor` probe 已經穩定。
7. `KubeArmor + runc` 在這輪仍呈現明顯邊界：
   - `service account token read`: PASS
   - sensitive file read: PASS
   - process execution block: FAIL
   - curl TCP egress block: FAIL

## 失敗案例總整

如果你要直接看失敗，不要只看總表，請看：

- [testing/failure-catalog-2026-06-09.md](/Users/hwchiu/hwchiu/openqq/testing/failure-catalog-2026-06-09.md)

這份文件已把這輪所有 `FAIL` 案例整理成：

1. 現象
2. 原始 JSON
3. 直接錯誤訊息
4. 目前判讀

## 環境逐一判讀

### 1. `k3s-gvisor`

- [nodes-ready.json](/Users/hwchiu/hwchiu/openqq/testing/raw/comparison-matrix-live-2026-06-09/k3s-gvisor/nodes-ready.json): PASS
- [baseline-pod.json](/Users/hwchiu/hwchiu/openqq/testing/raw/comparison-matrix-live-2026-06-09/k3s-gvisor/baseline-pod.json): PASS
- [istio-control-plane.json](/Users/hwchiu/hwchiu/openqq/testing/raw/comparison-matrix-live-2026-06-09/k3s-gvisor/istio-control-plane.json): PASS
- [istio-sidecar-smoke.json](/Users/hwchiu/hwchiu/openqq/testing/raw/comparison-matrix-live-2026-06-09/k3s-gvisor/istio-sidecar-smoke.json): PASS
- [gvisor-runtime.json](/Users/hwchiu/hwchiu/openqq/testing/raw/comparison-matrix-live-2026-06-09/k3s-gvisor/gvisor-runtime.json): FAIL
- [istio-gvisor-sidecar.json](/Users/hwchiu/hwchiu/openqq/testing/raw/comparison-matrix-live-2026-06-09/k3s-gvisor/istio-gvisor-sidecar.json): FAIL

判讀：
- CRI-O 1.31 上的 `runsc` 還沒有進入「裸 probe 可穩定成功」的狀態。
- 但叢集基線與一般 Istio sidecar 並沒有壞掉。
- 問題集中在 `RuntimeClass gvisor` workload 本身，以及 sidecar 疊上去之後的 ready 行為。
- 直接錯誤與事件已整理到 [testing/failure-catalog-2026-06-09.md](/Users/hwchiu/hwchiu/openqq/testing/failure-catalog-2026-06-09.md)

### 2. `k3s-openshell-runc`

- [nodes-ready.json](/Users/hwchiu/hwchiu/openqq/testing/raw/comparison-matrix-live-2026-06-09/k3s-openshell-runc/nodes-ready.json): PASS
- [baseline-pod.json](/Users/hwchiu/hwchiu/openqq/testing/raw/comparison-matrix-live-2026-06-09/k3s-openshell-runc/baseline-pod.json): PASS
- [istio-control-plane.json](/Users/hwchiu/hwchiu/openqq/testing/raw/comparison-matrix-live-2026-06-09/k3s-openshell-runc/istio-control-plane.json): PASS
- [istio-sidecar-smoke.json](/Users/hwchiu/hwchiu/openqq/testing/raw/comparison-matrix-live-2026-06-09/k3s-openshell-runc/istio-sidecar-smoke.json): PASS
- [openshell-control-plane.json](/Users/hwchiu/hwchiu/openqq/testing/raw/comparison-matrix-live-2026-06-09/k3s-openshell-runc/openshell-control-plane.json): PASS
- [openshell-guardrails.json](/Users/hwchiu/hwchiu/openqq/testing/raw/comparison-matrix-live-2026-06-09/k3s-openshell-runc/openshell-guardrails.json): PASS

判讀：
- 這仍然是目前最完整、最穩的主線。
- `Istio` 沒有破壞 OpenShell 的 control plane 與 guardrails。
- 目前 repo 內所有完整展示 OpenShell 能力的結論，仍應以這條路為主。

### 3. `k3s-openshell-gvisor`

- [nodes-ready.json](/Users/hwchiu/hwchiu/openqq/testing/raw/comparison-matrix-live-2026-06-09/k3s-openshell-gvisor/nodes-ready.json): PASS
- [baseline-pod.json](/Users/hwchiu/hwchiu/openqq/testing/raw/comparison-matrix-live-2026-06-09/k3s-openshell-gvisor/baseline-pod.json): PASS
- [istio-control-plane.json](/Users/hwchiu/hwchiu/openqq/testing/raw/comparison-matrix-live-2026-06-09/k3s-openshell-gvisor/istio-control-plane.json): PASS
- [istio-sidecar-smoke.json](/Users/hwchiu/hwchiu/openqq/testing/raw/comparison-matrix-live-2026-06-09/k3s-openshell-gvisor/istio-sidecar-smoke.json): PASS
- [gvisor-runtime.json](/Users/hwchiu/hwchiu/openqq/testing/raw/comparison-matrix-live-2026-06-09/k3s-openshell-gvisor/gvisor-runtime.json): FAIL
- [istio-gvisor-sidecar.json](/Users/hwchiu/hwchiu/openqq/testing/raw/comparison-matrix-live-2026-06-09/k3s-openshell-gvisor/istio-gvisor-sidecar.json): FAIL
- [openshell-control-plane.json](/Users/hwchiu/hwchiu/openqq/testing/raw/comparison-matrix-live-2026-06-09/k3s-openshell-gvisor/openshell-control-plane.json): PASS
- [openshell-guardrails.json](/Users/hwchiu/hwchiu/openqq/testing/raw/comparison-matrix-live-2026-06-09/k3s-openshell-gvisor/openshell-guardrails.json): PASS

判讀：
- 這一輪最值得記錄的變化是：`OpenShell guardrails` 在 `gVisor + CRI-O 1.31` 下是 `PASS`。
- 但這不代表 `gVisor` 本身已經穩。因為獨立的 `RuntimeClass gvisor` probe 仍然 `FAIL`。
- 也就是說，這條路目前更像「OpenShell sandbox 路徑可用，但裸 gVisor probe 與 sidecar-gVisor workload 仍不穩」。
- 相關失敗 log 與 timeout 訊息已整理到 [testing/failure-catalog-2026-06-09.md](/Users/hwchiu/hwchiu/openqq/testing/failure-catalog-2026-06-09.md)

### 4. `k3s-kubearmor-runc`

- [nodes-ready.json](/Users/hwchiu/hwchiu/openqq/testing/raw/comparison-matrix-live-2026-06-09/k3s-kubearmor-runc/nodes-ready.json): PASS
- [baseline-pod.json](/Users/hwchiu/hwchiu/openqq/testing/raw/comparison-matrix-live-2026-06-09/k3s-kubearmor-runc/baseline-pod.json): PASS
- [istio-control-plane.json](/Users/hwchiu/hwchiu/openqq/testing/raw/comparison-matrix-live-2026-06-09/k3s-kubearmor-runc/istio-control-plane.json): PASS
- [istio-sidecar-smoke.json](/Users/hwchiu/hwchiu/openqq/testing/raw/comparison-matrix-live-2026-06-09/k3s-kubearmor-runc/istio-sidecar-smoke.json): PASS
- [kubearmor-sa-block.json](/Users/hwchiu/hwchiu/openqq/testing/raw/comparison-matrix-live-2026-06-09/k3s-kubearmor-runc/kubearmor-sa-block.json): PASS
- [kubearmor-file-block.json](/Users/hwchiu/hwchiu/openqq/testing/raw/comparison-matrix-live-2026-06-09/k3s-kubearmor-runc/kubearmor-file-block.json): PASS
- [kubearmor-process-block.json](/Users/hwchiu/hwchiu/openqq/testing/raw/comparison-matrix-live-2026-06-09/k3s-kubearmor-runc/kubearmor-process-block.json): FAIL
- [kubearmor-network-block.json](/Users/hwchiu/hwchiu/openqq/testing/raw/comparison-matrix-live-2026-06-09/k3s-kubearmor-runc/kubearmor-network-block.json): FAIL

判讀：
- `KubeArmor` 這輪不是完全失敗，也不是完全成熟。
- 它對 `secret/file` 類保護有實際效果。
- 但對 `process` 與 `network egress` 類場景，這輪依然沒有擋住。
- 如果要把這條路拿去做 agentic workload 保護，目前不能誇大成「全面 runtime guardrail」。
- `/usr/bin/sleep` 與 `/usr/bin/curl` 的失敗證據已整理到 [testing/failure-catalog-2026-06-09.md](/Users/hwchiu/hwchiu/openqq/testing/failure-catalog-2026-06-09.md)

## Istio 影響摘要

1. 四套環境都能安裝 `Istio 1.30.1` control plane。
2. 四套環境的一般 sidecar injection smoke test 都通過。
3. 只有當 workload 直接指定 `runtimeClassName: gvisor` 時，Istio sidecar 組合失敗。
4. `OpenShell + runc` 與 `KubeArmor + runc` 在裝上 Istio 後都沒有立刻退化。

## 對後續文件的影響

這一輪結果應該推翻或修正以下舊敘事：

1. `OpenShell + gVisor` 不應再直接寫成「guardrails degraded」
2. `Istio sidecar smoke` 不應再寫成四套都 fail
3. `KubeArmor` 不應再只用 `service account token` 單一案例代表整體能力
4. `gVisor` 應明確拆成：
   - bare runtime probe: FAIL
   - Istio + gVisor sidecar: FAIL
   - OpenShell guardrails path: PASS
