# Four-Environment Live Comparison Report (2026-06-08)

這份報告記錄 2026-06-08 在 Azure 上重新建立四套環境後，以同一套 matrix 測試案例得到的 live 結果。

其中：

- `k3s-gvisor`
- `k3s-openshell-runc`
- `k3s-openshell-gvisor`

是 2026-06-08 白天的 live rerun 結果。

`k3s-kubearmor-runc` 則在同日晚間完成 root cause 修正後，重新做 clean rebuild 驗證並更新狀態。

## 本次重建的環境

1. `k3s-gvisor`
2. `k3s-openshell-runc`
3. `k3s-openshell-gvisor`
4. `k3s-kubearmor-runc`

## 結果摘要

| Test Case | k3s-gvisor | k3s-openshell-runc | k3s-openshell-gvisor | k3s-kubearmor-runc |
| --- | --- | --- | --- | --- |
| `nodes-ready` | PASS | PASS | PASS | PASS |
| `baseline-pod` | PASS | PASS | PASS | PASS |
| `gvisor-runtime` | PASS | N/A | PASS | N/A |
| `istio-control-plane` | PASS | PASS | PASS | PASS |
| `istio-sidecar-smoke` | PASS | PASS | PASS | PASS |
| `istio-gvisor-sidecar` | FAIL | N/A | FAIL | N/A |
| `openshell-control-plane` | N/A | PASS | PASS | N/A |
| `openshell-guardrails` | N/A | PASS | DEGRADED | N/A |
| `kubearmor-sa-block` | N/A | N/A | N/A | PASS |
| `kubearmor-file-block` | N/A | N/A | N/A | PASS |
| `kubearmor-process-block` | N/A | N/A | N/A | FAIL |
| `kubearmor-network-block` | N/A | N/A | N/A | FAIL |

## 關鍵結論

1. `k3s + gVisor` 基線正常
   - 三節點 Ready
   - `RuntimeClass/gvisor` probe 成功
   - `runsc` 確實在 guest kernel 內執行

2. `k3s + OpenShell + runc` 仍然是最完整主線
   - OpenShell control plane 正常
   - `L7` guardrails 正常
   - filesystem policy 正常
   - 本次 live evidence: [matrix-k3s-openshell-runc-1780925079](/Users/hwchiu/hwchiu/openqq/testing/raw/matrix-k3s-openshell-runc-1780925079)

3. `k3s + OpenShell + gVisor` 如預期退化
   - OpenShell control plane 正常
   - `L7` guardrails 仍成立
   - filesystem policy 退化為 `DEGRADED`
   - 本次 live evidence: [matrix-k3s-openshell-gvisor-1780925123](/Users/hwchiu/hwchiu/openqq/testing/raw/matrix-k3s-openshell-gvisor-1780925123)

4. `k3s + KubeArmor + runc` 已修正成成功案例
   - clean rebuild 後，KubeArmor enforcement 會穩定進入正確狀態
   - `block-service-account-token` 已能擋住 token read
   - 這次不是手動 restart 補救，而是 install script 自動完成

5. Istio 不會破壞既有 `runc` 路徑的 OpenShell / KubeArmor 基本能力
   - control plane 在四套叢集都正常
   - 一般 sidecar injection smoke test 在四套叢集都可通過
   - `OpenShell + runc` 的 guardrails 在安裝 Istio 後仍維持 `PASS`
   - `KubeArmor + runc` 的 token block 在安裝 Istio 後仍維持 `PASS`

6. `RuntimeClass gvisor` 與 Istio sidecar dataplane 目前不相容
   - 不是 injection 失敗
   - 是 `istio-init` 在 gVisor workload 內 crashloop
   - 直接錯誤是 `iptables nat` 無法初始化
   - 這表示目前不能宣稱 `gVisor` workload 可直接吃傳統 Istio sidecar 路徑

## 重要觀察

### OpenShell + runc

- `openshell-guardrails`: `PASS`
- 結論: `L7 and filesystem guardrails both held`

### OpenShell + gVisor

- `openshell-guardrails`: `DEGRADED`
- 結論: `L7 guardrails held, but filesystem policy degraded`

這和之前的根因分析一致：
- `gVisor` 路徑對 `Landlock` syscall 能力不足
- 所以 filesystem policy 不能像 `runc` 路徑一樣成立

### KubeArmor + runc

- `kubearmor-sa-block`: `PASS`
- 直接結果: service account token 讀取被拒絕
- 這次 root cause 是安裝時序，不是 policy YAML 本身寫錯
- 詳細報告：
  - [kubearmor-hardening-2026-06-08.md](/Users/hwchiu/hwchiu/openqq/testing/kubearmor-hardening-2026-06-08.md)
  - [kubearmor-agentic-scenarios-2026-06-08.md](/Users/hwchiu/hwchiu/openqq/testing/kubearmor-agentic-scenarios-2026-06-08.md)

### Istio 疊加影響

- `istio-control-plane`: 四套環境全部 `PASS`
- `istio-sidecar-smoke`: 四套環境全部 `PASS`
- `istio-gvisor-sidecar`: 在 `k3s-gvisor` 與 `k3s-openshell-gvisor` 兩條線都 `FAIL`

失敗不是 sidecar webhook 沒打進去，而是打進去後：

- pod 帶有 `sidecar.istio.io/status`
- `istio-init` / `istio-proxy` 已被注入
- 但 `istio-init` CrashLoopBackOff

最直接的錯誤是：

```text
iptables v1.8.10 (legacy): can't initialize iptables table `nat': Table does not exist
```

詳細影響已拆到：

- [istio-impact-2026-06-08.md](/Users/hwchiu/hwchiu/openqq/testing/istio-impact-2026-06-08.md)

## 對應資料檔

- matrix catalog: [testing/matrix/catalog.json](/Users/hwchiu/hwchiu/openqq/testing/matrix/catalog.json)
- matrix runner: [scripts/run-comparison-matrix-tests.sh](/Users/hwchiu/hwchiu/openqq/scripts/run-comparison-matrix-tests.sh)
- Istio install helpers:
  - [scripts/install-istio-comparison.sh](/Users/hwchiu/hwchiu/openqq/scripts/install-istio-comparison.sh)
  - [scripts/install-istio-stack.sh](/Users/hwchiu/hwchiu/openqq/scripts/install-istio-stack.sh)
- Istio reports:
  - [testing/istio-impact-2026-06-08.md](/Users/hwchiu/hwchiu/openqq/testing/istio-impact-2026-06-08.md)
- KubeArmor hardening evidence:
  - [testing/raw/kubearmor-hardening-2026-06-08](/Users/hwchiu/hwchiu/openqq/testing/raw/kubearmor-hardening-2026-06-08)

## 目前 Azure 狀態

這四套環境目前都還在 Azure 上運行，尚未清除：

1. `rg-k3s-gvisor`
2. `rg-k3s-openshell-runc`
3. `rg-k3s-openshell-gvisor`
4. `rg-k3s-kubearmor-runc`

如果要回收成本，可執行：

```bash
./scripts/destroy-comparison-matrix.sh
```
