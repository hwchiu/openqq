# OpenShell Runtime Assessment

日期: 2026-06-03
範圍: Azure `k3s` 測試環境，對照 `runc + OpenShell` 與 `gVisor + OpenShell`

## Executive Summary

目前的實驗結果支持以下結論:

1. OpenShell 可以穩定部署在 Azure 上的 3-node `k3s` 叢集
2. `runc + OpenShell` 是目前功能最完整的組合
3. `gVisor + OpenShell` 可以保留 network / L7 / policy hot-reload 等行為治理能力
4. 但 `gVisor + OpenShell` 目前不能保留 OpenShell 的 filesystem policy
5. 根因已確認為 `landlock_create_ruleset` 在 gVisor 路徑回 `ENOSYS`

## Platform Decision

### 若優先考量功能完整性

建議採用:

- `runc + OpenShell`

理由:

- 預設 deny egress 成立
- binary allowlist 成立
- L7 method/path policy 成立
- policy hot-reload 成立
- filesystem policy / Landlock 成立

### 若優先考量 runtime / kernel 邊界

可考慮採用:

- `gVisor + OpenShell`

但必須接受:

- filesystem policy 退化
- `Landlock Filesystem Sandbox Unavailable`
- `landlock_create_ruleset` syscall 未實作

## Security Interpretation

這份結果不支持把 `gVisor` 簡化為「更安全的升級版」。

更精準的說法是:

- `runc + OpenShell` 提供更完整的 OpenShell 原生能力
- `gVisor + OpenShell` 提供更強的 runtime 邊界，但失去部分 OpenShell enforcement

也就是兩條路徑的保護面不同，而不是單純高低優劣。

## Recommended Next Step

最有價值的下一步是:

1. 保留 `runc` 作為主路徑
2. 保留 `gVisor` 作為對照與隔離強化支線
3. 進一步驗證 `Kata Containers + OpenShell`

如果 `Kata` 能同時保留 OpenShell filesystem policy，並提供更強的 VM 邊界，它會是下一個最值得投資的組合。

## Evidence Map

- gVisor 驗證報告: [testing/openshell-gvisor-validation-2026-06-03.md](/Users/hwchiu/hwchiu/openqq/testing/openshell-gvisor-validation-2026-06-03.md)
- Landlock 根因報告: [testing/landlock-gvisor-root-cause-2026-06-03.md](/Users/hwchiu/hwchiu/openqq/testing/landlock-gvisor-root-cause-2026-06-03.md)
- runc 基準組報告: [testing/openshell-sandbox-validation-2026-06-03.md](/Users/hwchiu/hwchiu/openqq/testing/openshell-sandbox-validation-2026-06-03.md)
