# Istio Impact - 2026-06-09

這份報告只聚焦 `Istio 1.30.1` 疊到四套 `K3s 1.31 + CRI-O 1.31` 環境後的影響。

## 結論

1. 四套環境的 `istiod` 都能成功安裝並 ready。
2. 四套環境的一般 sidecar injection smoke test 都是 `PASS`。
3. 兩套 `gVisor` 環境上的 `RuntimeClass gvisor` + sidecar workload 都是 `FAIL`。
4. `OpenShell + runc` 在裝上 Istio 後仍是 `PASS`。
5. `OpenShell + gVisor` 在裝上 Istio 後，OpenShell guardrails 也仍是 `PASS`。
6. `KubeArmor + runc` 在裝上 Istio 後，token/file 仍可擋，但 process/network 還是失敗。

## per-stack 結果

| 環境 | Istio Control Plane | 一般 Sidecar Smoke | gVisor Sidecar | 其他疊加結果 |
| --- | --- | --- | --- | --- |
| `k3s-gvisor` | PASS | PASS | FAIL | 裸 `gvisor-runtime` probe FAIL |
| `k3s-openshell-runc` | PASS | PASS | N/A | OpenShell guardrails PASS |
| `k3s-openshell-gvisor` | PASS | PASS | FAIL | OpenShell guardrails PASS |
| `k3s-kubearmor-runc` | PASS | PASS | N/A | KubeArmor token/file PASS, process/network FAIL |

## 重點判讀

### 一般 sidecar injection

這次四套環境都通過：
- [k3s-gvisor/istio-sidecar-smoke.json](/Users/hwchiu/hwchiu/openqq/testing/raw/comparison-matrix-live-2026-06-09/k3s-gvisor/istio-sidecar-smoke.json)
- [k3s-openshell-runc/istio-sidecar-smoke.json](/Users/hwchiu/hwchiu/openqq/testing/raw/comparison-matrix-live-2026-06-09/k3s-openshell-runc/istio-sidecar-smoke.json)
- [k3s-openshell-gvisor/istio-sidecar-smoke.json](/Users/hwchiu/hwchiu/openqq/testing/raw/comparison-matrix-live-2026-06-09/k3s-openshell-gvisor/istio-sidecar-smoke.json)
- [k3s-kubearmor-runc/istio-sidecar-smoke.json](/Users/hwchiu/hwchiu/openqq/testing/raw/comparison-matrix-live-2026-06-09/k3s-kubearmor-runc/istio-sidecar-smoke.json)

這表示 `CRI-O 1.31` 基線下，Istio 對一般 workload 的 sidecar injection 並沒有把四套叢集打壞。

### gVisor workload + sidecar

這次兩套都失敗：
- [k3s-gvisor/istio-gvisor-sidecar.json](/Users/hwchiu/hwchiu/openqq/testing/raw/comparison-matrix-live-2026-06-09/k3s-gvisor/istio-gvisor-sidecar.json)
- [k3s-openshell-gvisor/istio-gvisor-sidecar.json](/Users/hwchiu/hwchiu/openqq/testing/raw/comparison-matrix-live-2026-06-09/k3s-openshell-gvisor/istio-gvisor-sidecar.json)

結果是 `server` 與 `client` rollout 都 timeout。這表示目前 repo 不能把 `Istio + RuntimeClass gvisor` 當成可用組合。

### OpenShell 疊加後

- `OpenShell + runc`: PASS
- `OpenShell + gVisor`: PASS

這很重要，因為它代表 Istio 本身不是這輪 OpenShell 問題的主因。

## 建議

1. 如果你要 mesh + OpenShell 的穩定主線，優先用 `k3s-openshell-runc`。
2. 如果你要驗證 `gVisor`，把「OpenShell sandbox 路徑」和「裸 gVisor workload + sidecar」分開看，不要混成一個結論。
3. 文件中應避免寫成「gVisor 不能裝 Istio」；正確說法是「gVisor workload 不能和這條 sidecar dataplane 穩定組合」。
