# Decision Lab Workflow

這份文件定義未來這個 repo 的正式工作流程，目的是讓 Azure 實驗、結果整理與 GitHub Pages 更新都走同一條路，不再回到零散 `testing/` 報告堆。

## 1. 建立 Azure 環境

先準備：

- `AZURE_SUBSCRIPTION_ID`
- `AZURE_TENANT_ID`
- SSH public key
- Terraform 所需的共用參數

建議把共用值放在：

- `terraform/stacks/common.auto.tfvars`

建立機器時，原則是每個 baseline 與 solution 都要能被明確對應：

1. `baseline`
2. `solution`
3. `run id`

命名原則不能只看人腦記憶，要能讓 raw archive 與 current-state 對得回去。

## 2. 選定 baseline

所有實驗都必須先選定其中一條平台配對：

1. `K8s 1.31 + CRI-O 1.31`
2. `K8s 1.34 + CRI-O 1.34`

不能把不同 baseline 的結果混成同一個敘事。

## 3. 選定 candidate solution

目前正式比較對象：

1. `k8s + cri-o`
2. `k8s + OpenShell + cri-o`
3. `k8s + gVisor`
4. `k8s + OpenShell + gVisor`
5. `k8s + cri-o + KubeArmor`

## 4. 宣告 guardrail / policy / config

每個 solution 都必須在明確宣告的設定下被比較。

不能用：

- default behavior
- 模糊預設狀態
- 沒寫清楚的 policy 意圖

每個 scenario 都應記錄：

- `allowed behavior`
- `blocked behavior`

## 5. 執行實驗

所有候選都要按固定層次執行：

1. `Provision`
2. `Install / Bootstrap`
3. `Baseline Readiness`
4. `Scenario Results`

如果前一層失敗，後一層不是 `N/A`，而是：

- `Blocked by solution failure`

## 6. 保存 raw archive

每次執行都要保留完整 raw outputs：

- 指令輸出
- JSON 結果
- log
- policy 檔
- 相關 manifest

raw archive 是追溯層，不是遠端閱讀主入口。

## 7. 更新 current-state

完成實驗後，不是再寫一份新的獨立報告，而是更新：

- `docs/data/current-state.json`

這個檔案只保存目前官方最新判讀需要的狀態。

至少要更新：

- baseline
- solution
- scenario
- status
- blocked reason
- latest interpretation

## 8. 更新 GitHub Pages

GitHub Pages 是正式閱讀入口，應更新同一套頁面：

- `docs/index.html`
- `docs/matrix.html`
- `docs/failures.html`
- `docs/evidence.html`
- `docs/tracks/*.html`

首頁先回答：

- 目前最推薦哪個 solution
- 推薦成立在哪條 baseline
- 哪些 scenario 已證明
- 哪些 solution 被 blocked

## 9. Push 到 Git

完成後應推回遠端，讓另一台機器或遠端閱讀者能直接看最新網站與資料。

建議最少做這些檢查後再 push：

- `python3 -m json.tool docs/data/current-state.json >/dev/null`
- `node --check docs/assets/content.js`
- `node --check docs/assets/site.js`
- 本地 `http.server`
- Playwright 開頁驗證
