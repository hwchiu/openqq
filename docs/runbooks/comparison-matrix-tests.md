# Comparison Matrix Test Flow

這份 runbook 說明四環境共用測試在 `2026-06-09` 之後的資料流與目前 test catalog。

## 資料流

1. `testing/matrix/catalog.json`
   - 定義 stacks 與 tests
2. `scripts/tests/*.sh`
   - 每個測試案例的 runner
3. `testing/raw/comparison-matrix-live-2026-06-09/`
   - 這輪 live rerun 的原始 JSON 證據
4. `testing/comparison-matrix-live-2026-06-09.md`
   - 人類可讀的主報告
5. `docs/data/comparison-matrix.json`
   - GitHub Pages 使用的發佈資料

## 目前測試集合

1. `nodes-ready`
2. `baseline-pod`
3. `istio-control-plane`
4. `istio-sidecar-smoke`
5. `gvisor-runtime`
6. `istio-gvisor-sidecar`
7. `openshell-control-plane`
8. `openshell-guardrails`
9. `kubearmor-sa-block`
10. `kubearmor-process-block`
11. `kubearmor-file-block`
12. `kubearmor-network-block`

## 06-09 重點

- 一般 Istio sidecar smoke: 四套全部 `PASS`
- `RuntimeClass gvisor` bare probe: 兩套 gVisor 路線都 `FAIL`
- `Istio + RuntimeClass gvisor`: 兩套 gVisor 路線都 `FAIL`
- `OpenShell + runc`: control plane / guardrails 都 `PASS`
- `OpenShell + gVisor`: control plane / guardrails 都 `PASS`
- `KubeArmor + runc`: `SA token` / `file block` `PASS`，`process` / `network` `FAIL`

## 目前推薦的結果來源

如果你要看最新 live 結果，不要只看 `testing/results/latest/`，優先看：

- [testing/comparison-matrix-live-2026-06-09.md](/Users/hwchiu/hwchiu/openqq/testing/comparison-matrix-live-2026-06-09.md)
- [testing/raw/comparison-matrix-live-2026-06-09/summary.json](/Users/hwchiu/hwchiu/openqq/testing/raw/comparison-matrix-live-2026-06-09/summary.json)
