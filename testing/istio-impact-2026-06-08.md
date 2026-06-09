# Istio Impact Across Four Stacks (2026-06-08)

這份報告整理 2026-06-08 在四套比較環境上安裝 Istio 1.30.1 之後的實際影響。

目標不是驗證 Istio 本身功能完整，而是回答：

1. 裝上 Istio control plane 之後，四套架構是否還能正常運作
2. 一般 sidecar injection 是否會破壞既有測試
3. `RuntimeClass gvisor` workload 與傳統 Istio sidecar dataplane 是否相容

## 測試環境

1. `k3s-gvisor`
2. `k3s-openshell-runc`
3. `k3s-openshell-gvisor`
4. `k3s-kubearmor-runc`

安裝腳本：

- [scripts/install-istio-comparison.sh](/Users/hwchiu/hwchiu/openqq/scripts/install-istio-comparison.sh)
- [scripts/install-istio-stack.sh](/Users/hwchiu/hwchiu/openqq/scripts/install-istio-stack.sh)

## 測試案例

1. `istio-control-plane`
2. `istio-sidecar-smoke`
3. `istio-gvisor-sidecar`
4. `openshell-guardrails` after Istio
5. `kubearmor-sa-block` after Istio

## 結果摘要

| Test Case | k3s-gvisor | k3s-openshell-runc | k3s-openshell-gvisor | k3s-kubearmor-runc |
| --- | --- | --- | --- | --- |
| `istio-control-plane` | PASS | PASS | PASS | PASS |
| `istio-sidecar-smoke` | PASS | PASS | PASS | PASS |
| `istio-gvisor-sidecar` | FAIL | N/A | FAIL | N/A |
| `openshell-guardrails` | N/A | PASS | DEGRADED | N/A |
| `kubearmor-sa-block` | N/A | N/A | N/A | PASS |

## 1. Control plane 狀態

結果：四套環境全部 `PASS`

Istio control plane 在四套環境都成功進入 ready，版本一致為：

```text
istiod-1.30.1
```

這代表：

- 安裝 Istio 不會直接破壞四套叢集的基本可用性
- `istiod` 在四套叢集都能正常建立

## 2. 一般 sidecar injection smoke test

結果：四套環境全部 `PASS`

這個 smoke test 使用一般 workload，不指定 `runtimeClassName: gvisor`，只驗證：

1. namespace 自動 injection 可用
2. pod 能看到 `sidecar.istio.io/status`
3. `istio-init` / `istio-proxy` 已被注入
4. client 透過 mesh 內服務可拿到預期回應

關鍵點：

- sidecar 是否存在，不能只看 `spec.containers`
- 這次實測中，`istio-init` 與 `istio-proxy` 出現在 `spec.initContainers`
- annotation `sidecar.istio.io/status` 是更可靠的判讀訊號

這也是為什麼後來我修正了：

- [scripts/tests/istio-sidecar-smoke.sh](/Users/hwchiu/hwchiu/openqq/scripts/tests/istio-sidecar-smoke.sh)
- [scripts/tests/istio-gvisor-sidecar.sh](/Users/hwchiu/hwchiu/openqq/scripts/tests/istio-gvisor-sidecar.sh)

讓腳本同時檢查：

- `spec.containers`
- `spec.initContainers`
- `sidecar.istio.io/status`

## 3. `RuntimeClass gvisor` + Istio sidecar

結果：

- `k3s-gvisor`: `FAIL`
- `k3s-openshell-gvisor`: `FAIL`

這個案例與上一節不同，它故意讓 workload 帶上：

```yaml
runtimeClassName: gvisor
```

然後再讓 Istio 自動注入 sidecar。

### 失敗型態

失敗不是：

- webhook 沒打到
- sidecar 沒注入
- service 不通而已

實際上：

- pod 會帶有 `sidecar.istio.io/status`
- `istio-init` / `istio-proxy` 都被注入
- 但 pod 停在 `Init:CrashLoopBackOff`

事件明確顯示：

```text
Back-off restarting failed container istio-init
```

### 直接根因證據

從 `istio-init` log 可以直接看到：

```text
iptables v1.8.10 (legacy): can't initialize iptables table `nat': Table does not exist
```

這表示目前這條路徑的問題是：

- sidecar dataplane 的 init 流程需要 `iptables nat`
- gVisor workload 內的 kernel / iptables 能力無法滿足這個需求

所以目前能誠實下的結論是：

- `gVisor` 本身不是不能和 Istio control plane 共存
- 但 `RuntimeClass gvisor` workload 不能直接走這條傳統 sidecar + init iptables 路徑

## 4. OpenShell 疊加 Istio 後的影響

### `k3s-openshell-runc`

結果：`PASS`

安裝 Istio 後重新跑 `openshell-guardrails`，結論不變：

- `L7` guardrails 成立
- filesystem policy 成立

也就是：

- Istio 不會把 `OpenShell + runc` 這條主線打壞

證據目錄：

- [matrix-k3s-openshell-runc-1780928880](/Users/hwchiu/hwchiu/openqq/testing/raw/matrix-k3s-openshell-runc-1780928880)

### `k3s-openshell-gvisor`

結果：`DEGRADED`

安裝 Istio 後重新跑 `openshell-guardrails`，結論仍和先前一致：

- `L7` guardrails 成立
- filesystem policy 仍退化

換句話說：

- Istio 沒有新增額外破壞
- 這條線的主要限制仍然來自 `gVisor` 對 filesystem enforcement 的退化

證據目錄：

- [matrix-k3s-openshell-gvisor-1780928908](/Users/hwchiu/hwchiu/openqq/testing/raw/matrix-k3s-openshell-gvisor-1780928908)

## 5. KubeArmor 疊加 Istio 後的影響

結果：`PASS`

安裝 Istio 後，`kubearmor-sa-block` 重新驗證仍為 `PASS`。

這表示：

- 在目前這條 `k3s + KubeArmor + runc` 路徑下
- 引入 Istio control plane 與一般 sidecar injection
- 不會直接破壞既有的 token-read block 成果

注意：

- 這不代表 KubeArmor 所有 process/network 類規則都沒問題
- 那部分的限制仍在：
  - [kubearmor-agentic-scenarios-2026-06-08.md](/Users/hwchiu/hwchiu/openqq/testing/kubearmor-agentic-scenarios-2026-06-08.md)

## 結論

1. Istio control plane 可安全疊加到四套環境
2. 一般 sidecar injection smoke test 在四套環境都可通過
3. `OpenShell + runc` 在裝上 Istio 後仍是最穩定主線
4. `OpenShell + gVisor` 的退化與 Istio 無關，核心仍是 filesystem enforcement
5. `RuntimeClass gvisor` workload 目前不適合直接走傳統 Istio sidecar dataplane
6. `KubeArmor + runc` 在裝上 Istio 後，至少 token block 這條驗證沒有退化

## 下一步

如果後續要繼續研究 Istio 方向，最值得補的不是再跑一次相同 smoke test，而是：

1. 針對 `gVisor` 研究不用 `istio-init` iptables 的資料面路徑
2. 驗證 OpenShell sandbox 與 sidecar 同時存在時，是否有更細的流量或啟動副作用
3. 把 KubeArmor 的 process/network 類問題和 Istio sidecar 疊加後再做一次對照
