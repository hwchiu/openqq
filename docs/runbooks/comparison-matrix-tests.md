# Comparison Matrix Test Flow

這份 runbook 專門解釋四環境共用測試是怎麼被執行與發佈的。

## 資料流

1. `testing/matrix/catalog.json`
   - 定義 stack 與 test case
2. `scripts/run-comparison-matrix-tests.sh`
   - 根據 catalog 執行 runner
3. `testing/results/latest/<stack>/<test>.json`
   - 每個測試的原始結果
4. `testing/results/latest/comparison-matrix.json`
   - 聚合後的結果
5. `docs/data/comparison-matrix.json`
   - GitHub Pages 使用的發佈版本

## 執行

```bash
./scripts/install-comparison-matrix.sh
PUBLISH_RESULTS=true ./scripts/run-comparison-matrix-tests.sh
```

## 目前測試集合

1. `nodes-ready`
2. `baseline-pod`
3. `gvisor-runtime`
4. `openshell-control-plane`
5. `openshell-guardrails`
6. `kubearmor-sa-block`

## 設計原則

- 不強迫每個測試適用所有環境
- 對不適用的環境明確標 `N/A`
- 對功能存在但退化的情況標 `DEGRADED`
- 對腳本已完成但尚未重新 live publish 的環境標 `PENDING`
