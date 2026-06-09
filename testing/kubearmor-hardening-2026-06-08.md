# KubeArmor Hardening Report (2026-06-08)

這份報告記錄 `k3s-kubearmor-runc` 在 2026-06-08 的 root cause 調查、修正方式，以及 clean rebuild 後的驗證結果。

## 問題定義

原始 matrix 案例 `kubearmor-sa-block` 失敗。

- 目標行為：demo workload 讀取 `/run/secrets/kubernetes.io/serviceaccount/token` 時應被 `KubeArmorPolicy` 擋下
- 原始結果：token read 成功
- 影響：不能誠實宣稱這條 `KubeArmor + runc` 路線已經完成 enforcement

## Root Cause

這次不是 policy YAML 寫錯，而是安裝時序有兩個缺口。

1. demo pod 建立早於 mutating/enforcement 路徑就緒
   - `kubearmor-demo` 在 webhook/controller 完全 ready 之前就被建立
   - 當時 Helm values 也還是 `kubearmorOperator.annotateExisting=false`
   - 結果是既有 workload 不會被回補處理

2. install script 對 KubeArmor 元件的時序假設太樂觀
   - Helm 先安裝的是 `kubearmor-operator`
   - `kubearmor-controller`、`kubearmor-relay`、`kubearmor-apparmor-containerd-*` 是 sample config 套用後，operator 再建立出來
   - 原腳本直接等待 `kubearmor-controller` rollout，可能在 deployment 尚未存在時就失敗

## 證據

### 失敗時的特徵

- `kubearmor-demo` 最初可直接讀取 service account token
- controller log 明確顯示：
  - `Not annotating existing resources as annotate existing is set to false`

### 最小假設驗證

我沒有先改 policy，而是只重建 `kubearmor-demo` workload。

結果：
- `/proc/1/attr/current` 變成 `kubearmor-default-kubearmor-demo-nginx (enforce)`
- 再次讀取 token 時被拒絕

這證明 block policy 本身有效，問題在 workload 建立時沒有走到正確的 KubeArmor enforcement 路徑。

### fresh evidence

- 節點與元件狀態：
  - [nodes.txt](/Users/hwchiu/hwchiu/openqq/testing/raw/kubearmor-hardening-2026-06-08/nodes.txt)
  - [kubearmor-components.txt](/Users/hwchiu/hwchiu/openqq/testing/raw/kubearmor-hardening-2026-06-08/kubearmor-components.txt)
- default namespace 內的 deployment / pod / KubeArmorPolicy：
  - [default-resources.yaml](/Users/hwchiu/hwchiu/openqq/testing/raw/kubearmor-hardening-2026-06-08/default-resources.yaml)
- process label 與 token block 證據：
  - [token-block.stdout](/Users/hwchiu/hwchiu/openqq/testing/raw/kubearmor-hardening-2026-06-08/token-block.stdout)
  - [token-block.stderr](/Users/hwchiu/hwchiu/openqq/testing/raw/kubearmor-hardening-2026-06-08/token-block.stderr)
- verifier 輸出：
  - [verifier.txt](/Users/hwchiu/hwchiu/openqq/testing/raw/kubearmor-hardening-2026-06-08/verifier.txt)
- matrix 單案結果：
  - [matrix-result.json](/Users/hwchiu/hwchiu/openqq/testing/raw/kubearmor-hardening-2026-06-08/matrix-result.json)

## 修正

修正集中在 [install-kubearmor-stack.sh](/Users/hwchiu/hwchiu/openqq/scripts/install-kubearmor-stack.sh)：

1. Helm install/upgrade 改成：
   - `--wait`
   - `--timeout 10m`
   - `--set kubearmorOperator.annotateExisting=true`

2. sample config 套用後，不再直接假設資源已存在
   - 先等待 `kubearmor-controller` 出現
   - 再等待 `kubearmor-relay` 出現
   - 再等待 `kubearmor-apparmor-containerd-*` daemonset 出現並 rollout 完成

3. workload 建立順序調整
   - 元件 ready 後才建立 `kubearmor-demo`
   - 再套用 demo policies

4. namespace visibility 補成：
   - `process,file,network,capabilities`

## Clean Rebuild 驗證

我不是在舊環境手動修補，而是直接：

1. `terraform_destroy_stack k3s-kubearmor-runc`
2. 重新執行 [install-k3s-kubearmor-runc.sh](/Users/hwchiu/hwchiu/openqq/scripts/install-k3s-kubearmor-runc.sh)
3. 再執行 [verify-kubearmor-runtime.sh](/Users/hwchiu/hwchiu/openqq/scripts/verify-kubearmor-runtime.sh)

最終結果：

- `stdout`: 空
- `stderr`: `Permission denied`
- verifier 結論：`service account token read was blocked`

另外，從 workload 內部讀到：

```text
kubearmor-default-kubearmor-demo-nginx (enforce)
```

這代表 demo workload 已被放進 KubeArmor enforce 狀態，而不是單純 policy 物件存在。

## 結論

目前 `k3s + KubeArmor + runc` 這條安裝路線已經從：

- `FAIL`

變成：

- `PASS`

而且這個 `PASS` 來自 clean rebuild 後的 install script，自動完成，不依賴手動 restart。

## 仍然保留的範圍限制

這次修好的是目前 matrix 裡的 `service account token block` 案例。

這不等於：

- 已完整驗證所有 KubeArmor file/process/network policy 變體
- 已做 namespace-level allowlist posture 設計
- 已完成和 OpenShell 同等深度的多維度 guardrail 比較

目前可以誠實宣稱的是：

- 這條 KubeArmor 安裝路線已經能穩定進入 enforce 狀態
- 既有的 `block-service-account-token` 測試案例已經成功
