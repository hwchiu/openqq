# OpenSandbox 靜態文件網站 TODO

這份清單追蹤 `openqq` GitHub Pages 文件網站的完整工作。完成項目需要能在本地瀏覽、在 GitHub Pages 發布，且內容與目前 OpenSandbox 的實際運作模型一致。

## A. 網站基礎

- [ ] 在 repo 根目錄建立 GitHub Pages 入口 `index.html`
- [ ] 使用零建置的 HTML/CSS/JavaScript，避免 GitHub Pages 需要額外 build pipeline
- [ ] 建立 responsive layout，驗證 375px、768px、1024px、1440px 寬度
- [ ] 使用高對比、可讀的 technical documentation visual system
- [ ] 使用 IBM Plex Sans + JetBrains Mono 字體組合
- [ ] 不使用 emoji 作為 UI icon，改用 inline SVG
- [ ] 加入鍵盤 focus、hover、reduced-motion 與語意化標籤
- [ ] 加入章節導覽與頁內 anchor
- [ ] 加入程式碼複製按鈕，失敗時仍可手動選取

## B. OpenSandbox 架構說明

- [ ] 說明 external client / agent 只呼叫 application backend API
- [ ] 說明 backend 持有 OpenSandbox credential，不將 Kubernetes credential 給 agent
- [ ] 說明 OpenSandbox server、controller、warm pool、sandbox、execd 的責任
- [ ] 加入完整架構圖：client → backend → OpenSandbox → pool/sandbox
- [ ] 加入 egress gateway、CoreDNS 與 external FQDN 的資料流
- [ ] 清楚區分 Kubernetes API server 與 OpenSandbox API server
- [ ] 說明 cluster 內部元件使用 private network

## C. Egress policy

- [ ] 說明每個 sandbox 預設 `default deny`
- [ ] baseline 允許 sandbox 與 OpenSandbox server 溝通
- [ ] baseline 允許 sandbox 透過 CoreDNS 進行 DNS 查詢
- [ ] 說明 DNS allow 不等於任意 Internet allow
- [ ] 定義 agent 透過 backend API 申請額外 FQDN 的流程
- [ ] 加入 FQDN 格式驗證：拒絕 URL path、IP、CIDR 與非法 hostname
- [ ] 加入 backend allowlist、quota、audit log 與 authorization 說明
- [ ] 說明 rule 以 `sandbox_id/session_id` 綁定
- [ ] 說明 sandbox release 或 TTL 到期時自動撤銷 egress rule
- [ ] 加入 dynamic FQDN request / revoke 的 API conceptual example

## D. Warm pool 與 TTL

- [ ] 說明平常預留 warm sandbox，例如 `min_available: 10`
- [ ] 說明 client 到達時優先 claim available sandbox
- [ ] 說明 pool 耗盡時立即建立新 sandbox，不要求 client 等待固定 queue
- [ ] 說明 claim 前清理 workspace，避免前一個 session 的資料外洩
- [ ] 說明 session 與 sandbox id 的綁定
- [ ] 將 TTL 定義為 300 秒 / 5 分鐘
- [ ] 說明 idle TTL 與單次 command timeout 的差異
- [ ] 說明 TTL 到期後清理 workspace、sandbox 與 egress rule
- [ ] 加入 lifecycle flow：available → claimed → active → idle → released

## E. Grafana / Prometheus observability

- [ ] 說明 Grafana datasource 連接 Prometheus 的責任
- [ ] 加入 warm pool 數量 panel
- [ ] 加入 sandbox Running / Ready panel
- [ ] 加入 sandbox、controller、server、execd、egress sidecar restart panel
- [ ] 加入 CPU 使用量 panel
- [ ] 加入 memory working set panel
- [ ] 加入 pod phase / readiness panel
- [ ] 加入 etcd leader、etcd storage 與 control-plane health panel
- [ ] 說明 Kubernetes metrics 與 OpenSandbox custom metrics 的差異
- [ ] 對每個 panel 提供 PromQL 或 metric 名稱
- [ ] 說明 pool allocation、claim latency、TTL release、egress deny 等 custom metrics 的建議格式
- [ ] 加入「看到異常後如何判讀」的 troubleshooting notes

## F. 不使用 SDK 的 OpenSandbox API 範例

- [ ] 使用 Python standard library 或 raw HTTP，不 import OpenSandbox SDK
- [ ] 示範 `POST /v1/sandboxes` 建立 session
- [ ] 示範使用 `poolRef` 優先認領 warm pool
- [ ] 示範保存同一個 `sandbox_id`
- [ ] 示範在同一 session 反覆呼叫 Execd `/command`
- [ ] 示範 SSE stdout / stderr event stream
- [ ] 示範 multipart `/files/upload`
- [ ] 示範 `/files/download` 下載 binary
- [ ] 示範 `/files/search` 列出 workspace 檔案
- [ ] 示範 session cleanup 與 `DELETE /v1/sandboxes/{sandbox_id}`
- [ ] 加入 command timeout、output limit、path allowlist 與 error handling
- [ ] 說明 API credential 只能留在 backend，不放進 browser

## G. GitHub Pages 發布與驗收

- [ ] 確認網站從 repo root 可由 GitHub Pages 發布
- [ ] 確認沒有依賴 localhost、Kubernetes cluster IP 或 private URL 才能閱讀文件
- [ ] 確認所有頁內連結可跳轉
- [ ] 確認程式碼區塊在手機寬度可水平捲動
- [ ] 確認頁面沒有 JavaScript console error
- [ ] 用本地 static server 驗證：`python3 -m http.server 8000`
- [ ] 驗證 HTML 基本結構與 meta description
- [ ] 檢查 git diff，避免把 credential、kubeconfig 或 cluster secret 放入網站
- [ ] 完成後提交 `index.html` 與本 TODO 更新

## 目前環境相關備註

- Grafana 目前使用 NodePort `55667`。
- Prometheus 與 Grafana 使用 PVC；目前 StorageClass 是 node-local `local-path`。
- OpenSandbox warm pool 與 egress 是 Kubernetes 叢集內部署設定，靜態網站只描述架構與 API contract，不嵌入任何 secret。
- 網站內容應使用概念化的 service URL 與 placeholder credential，避免暴露目前環境的 private IP、token 或密碼。
