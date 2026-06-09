# Agentic Security Expansion Report (2026-06-08)

這份報告把 2026-06-08 補強後的 agentic 測試內容集中整理，避免資訊分散在多份 runbook 與單項報告中。

它聚焦三件事：

1. `k3s-kubearmor-runc` 的 KubeArmor primitive 能力
2. `ModelArmor-style` lab 對 AI / agent 類場景的實測邊界
3. 疊加 Istio 後，這些結果是否立刻退化

## 範圍

本報告不重新描述四套環境的 Terraform 建置方式。  
建置請看：

- [docs/runbooks/install-comparison-matrix.md](/Users/hwchiu/hwchiu/openqq/docs/runbooks/install-comparison-matrix.md)
- [docs/runbooks/install-k3s-kubearmor-runc.md](/Users/hwchiu/hwchiu/openqq/docs/runbooks/install-k3s-kubearmor-runc.md)
- [docs/runbooks/modelarmor-lab.md](/Users/hwchiu/hwchiu/openqq/docs/runbooks/modelarmor-lab.md)
- [docs/runbooks/istio-comparison.md](/Users/hwchiu/hwchiu/openqq/docs/runbooks/istio-comparison.md)

## 測試類型

### KubeArmor primitive

1. service account token read
2. sensitive file read
3. process exec
4. network egress

### ModelArmor-style agentic

1. Python secret read
2. Python subprocess shell escape
3. Python HTTP egress
4. payload staging to `/tmp`
5. `pip install` to `/tmp`
6. `pip install + import`
7. `pickle`-driven code execution
8. in-cluster `download-and-exec`

### Istio 疊加

1. control plane ready
2. generic sidecar injection smoke
3. `RuntimeClass gvisor` + sidecar dataplane
4. OpenShell guardrails after Istio
5. KubeArmor token block after Istio

## 結果總覽

| Category | Scenario | Result | 核心判讀 |
| --- | --- | --- | --- |
| KubeArmor primitive | service account token read | PASS | secret guardrail 成立 |
| KubeArmor primitive | sensitive file read | PASS | file guardrail 成立 |
| KubeArmor primitive | process exec | FAIL | process enforcement 不穩 |
| KubeArmor primitive | network egress | FAIL | network enforcement 不穩 |
| ModelArmor-style | Python secret read | PASS | 最穩的一條防線 |
| ModelArmor-style | shell escape | FAIL | `/bin/sh` deny 未有效阻止執行 |
| ModelArmor-style | HTTP egress | FAIL | outbound callback 仍可成功 |
| ModelArmor-style | payload staging | DEGRADED | 可下載並寫入 `/tmp` |
| ModelArmor-style | `pip install` | DEGRADED | agent 可自行拉工具到暫存區 |
| ModelArmor-style | `pip install + import` | DEGRADED | agent 可完成自我擴展並立即使用 |
| ModelArmor-style | `pickle` RCE | FAIL | 不可信模型載入可直接帶出 code execution |
| ModelArmor-style | download-and-exec | FAIL | in-cluster 第二階段 payload 可成功執行 |
| Istio overlay | control plane ready | PASS | 四套環境都能裝 Istio |
| Istio overlay | generic sidecar smoke | PASS | 一般 sidecar injection 正常 |
| Istio overlay | gVisor workload + sidecar | FAIL | `istio-init` 需要 `iptables nat` |
| Istio overlay | OpenShell + runc guardrails | PASS | Istio 未破壞主線 |
| Istio overlay | OpenShell + gVisor guardrails | DEGRADED | 退化仍來自 filesystem enforcement |
| Istio overlay | KubeArmor token block | PASS | Istio 未破壞 token guardrail |

## 直接證據

### KubeArmor / ModelArmor-style

- [testing/kubearmor-hardening-2026-06-08.md](/Users/hwchiu/hwchiu/openqq/testing/kubearmor-hardening-2026-06-08.md)
- [testing/kubearmor-agentic-scenarios-2026-06-08.md](/Users/hwchiu/hwchiu/openqq/testing/kubearmor-agentic-scenarios-2026-06-08.md)
- [testing/modelarmor-install-assessment-2026-06-08.md](/Users/hwchiu/hwchiu/openqq/testing/modelarmor-install-assessment-2026-06-08.md)
- [testing/modelarmor-lab-validation-2026-06-08.md](/Users/hwchiu/hwchiu/openqq/testing/modelarmor-lab-validation-2026-06-08.md)
- raw evidence:
  - [testing/raw/modelarmor-lab-2026-06-08](/Users/hwchiu/hwchiu/openqq/testing/raw/modelarmor-lab-2026-06-08)
  - [testing/raw/kubearmor-hardening-2026-06-08](/Users/hwchiu/hwchiu/openqq/testing/raw/kubearmor-hardening-2026-06-08)

### Istio 疊加

- [testing/istio-impact-2026-06-08.md](/Users/hwchiu/hwchiu/openqq/testing/istio-impact-2026-06-08.md)
- [testing/comparison-matrix-live-2026-06-08.md](/Users/hwchiu/hwchiu/openqq/testing/comparison-matrix-live-2026-06-08.md)

## 判讀

### 1. 如果目標是防 `secret` / `file read`

目前這條 `KubeArmor + AppArmor` 路徑是可用的。  
至少這次的：

- service account token read
- sensitive file read
- Python secret read

都能穩定被擋下。

### 2. 如果目標是防 agent self-extension

目前不夠。

因為這次明確驗到：

- `pip install` 可成功
- `pip install + import` 可成功
- payload 可下載到 `/tmp`
- in-cluster `download-and-exec` 可成功

這表示 agent 可以：

- 拉下新工具
- 立刻 import 新模組
- 從叢集內部服務拿第二階段 payload
- 直接執行 script

### 3. 如果目標是防不可信模型載入

目前也不夠。

因為：

- `pickle` 反序列化可以直接帶出 `os.system()`

這表示把 `ModelArmor` 理解成「只要 KubeArmor 在 enforce 就能保護模型載入」是不成立的。

### 4. 如果目標是把 Istio 疊加進來

可以，但要分清楚：

- control plane 沒問題
- 一般 sidecar injection 沒問題
- `RuntimeClass gvisor` workload + 傳統 Istio sidecar dataplane 目前不行

## 最終結論

目前最誠實的結論是：

1. 這套環境已足夠證明 `secret/file` 類 guardrail 有價值
2. 這套環境還不足以宣稱能完整保護 agentic / AI workflow
3. 最大缺口在：
   - process execution
   - network egress
   - tool bootstrap
   - untrusted model load
   - second-stage payload execution
4. 如果要把這套方案對外描述成「適合 agentic」，應該非常謹慎，不能跳過這些 `FAIL / DEGRADED` 邊界
