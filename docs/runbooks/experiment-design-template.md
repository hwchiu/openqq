# Experiment Design Template

這份模板用來定義每次正式 scenario 設計，避免只留下零散測試腳本卻沒有清楚的實驗意圖。

## 1. Metadata

- `baseline`:
- `solution`:
- `scenario family`:
- `scenario id`:
- `date`:

## 2. Risk hypothesis

要驗證的風險是什麼？

例如：

- agent 寫入超出 workspace 範圍
- agent 讀取 service account token
- agent 對外呼叫未允許 API

## 3. Allowed behavior

哪些行為本來就應該成功？

## 4. Blocked behavior

哪些行為本來就應該被擋？

## 5. Declared guardrail or policy

明確寫出：

- OpenShell policy
- KubeArmor policy
- runtime config
- Istio injection condition
- 其他會影響結果的設定

## 6. Execution steps

列出可重複執行的步驟，不要只寫口頭描述。

## 7. Raw outputs

列出要保留的原始資料：

- stdout
- stderr
- describe
- logs
- policy manifest
- evidence JSON

## 8. Result classification

結果只能是：

1. `Executed and passed`
2. `Executed and failed`
3. `Blocked by solution failure`
4. `Not tested`

## 9. Current-state update rule

這次結果應如何反映到 `docs/data/current-state.json` 與 GitHub Pages？
