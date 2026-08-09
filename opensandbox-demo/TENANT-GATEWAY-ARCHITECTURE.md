# OpenSandbox Tenant Gateway 架構

## 1. 目標

Tenant Gateway 位於外部 client 與 OpenSandbox Server 之間，提供一個不需要
暴露 Kubernetes API credential，也不需要把 OpenSandbox Server key 發給使用者
的多租戶入口。

```text
Client / Agent
     |
     | tenant key
     v
Tenant Gateway
  - tenant authentication
  - quota / scope
  - sandbox ownership
  - warm-pool claim
  - egress policy
  - streaming proxy
  - tenant metrics
     |
     | one private server credential
     v
OpenSandbox Server
     |
     v
Warm Pool / Sandbox Pods
```

OpenSandbox Server 只負責 sandbox lifecycle 與 runtime 操作；tenant identity、
權限、配額與 audit context 由 Gateway 管理。

## 2. Gateway 必須提供的效果

### Tenant isolation

- 每個 tenant 使用自己的 tenant key。
- Gateway 只儲存 tenant key 的 hash，不儲存明文 key。
- API request 先解析 tenant，再執行 scope 與 quota 檢查。
- sandbox 建立後記錄 `sandbox_id -> tenant_id` ownership。
- tenant 只能 list、command、upload、download、delete 自己的 sandbox。
- OpenSandbox Server 的共同 server key 永遠不下發給 client。

### OpenSandbox API compatibility

Gateway 對外維持 OpenSandbox `/v1/...` API 形式，並在內部注入 server credential。
可以採用 allowlist，而不是無條件轉發所有路徑：

- sandbox create / list / get / delete
- lifecycle operations
- command proxy
- file upload / download proxy
- 明確拒絕 `/snapshot`、`/snapshots` 與未知 API

Upload、download 與 command output 必須採 streaming，並設定 request body、
response body、timeout 與 concurrency 上限，避免 Gateway 自身成為記憶體瓶頸。

## 3. DB 的責任

Gateway 需要一個 durable state store。這個 DB 不只是存 tenant key，也應該保存
跨請求需要的 ownership、egress、quota 與 audit 狀態。

### Tenant

```text
tenant_id
key_hash
enabled
scopes
max_concurrent_sandboxes
max_request_bytes
created_at
updated_at
rotated_at
```

`key_hash` 使用不可逆雜湊；新增 tenant 時只回傳一次明文 key。停用 tenant
不需要重啟 Gateway，之後的新 request 立即被拒絕。

### Sandbox ownership

```text
sandbox_id
tenant_id
pool_name
allocation_state       # creating / allocated / released / expired
claimed_at
last_activity_at
released_at
```

這張表用來阻止 tenant A 操作 tenant B 的 sandbox，也讓 Gateway 能將
OpenSandbox / Kubernetes resource metrics 透過 `sandbox_id` 關聯回 tenant。

### Egress grants

```text
grant_id
sandbox_id
tenant_id
fqdn
ports
state                  # requested / active / revoked / expired
requested_at
expires_at
revoked_at
```

`tenant_id` 與 `sandbox_id` 必須同時驗證，避免拿到 sandbox ID 後修改別人的
egress policy。FQDN 必須經過格式與 allowlist 驗證，不接受任意 URL、IP、CIDR
或 wildcard。

### Audit events

```text
event_id
tenant_id
sandbox_id
action
request_id
result
created_at
metadata
```

建議記錄 tenant create、key rotate、sandbox claim/release、egress allow/revoke、
quota rejection 與被拒絕的 API route，但不要將 tenant key、檔案內容或 command
secret 寫入 audit log。

## 4. Warm pool 與 egress 的整合

Warm pool 的 Pod 可能會被不同 tenant 依序使用，因此 claim 不是單純把一個
sandbox ID 回傳給 client，而是一個需要 transaction 與安全清理的流程。

```text
1. Gateway 收到 create request
2. 驗證 tenant、scope 與 quota
3. 認領 warm-pool sandbox；沒有可用資源才建立新的 sandbox
4. 建立 sandbox ownership record
5. reset egress policy
6. 套用 baseline policy：default deny、必要的 control-plane access
7. 確認 reset 成功後才回傳 sandbox
```

如果 egress reset 失敗，Gateway 必須將 sandbox 標記為 `quarantine`，不能交付
給 tenant。

### Egress state machine

```text
NO_EGRESS
  - default deny
  - 不允許 DNS

DNS_ENABLED
  - 只允許 sandbox -> CoreDNS
  - 尚未允許任何外部 FQDN

FQDN_ENABLED
  - 允許 CoreDNS
  - 只允許 tenant 已申請的 FQDN / port
```

初始 claim、release 與 TTL expiry 都應該執行 reset：

```text
default deny
remove all old FQDN grants
remove DNS access when no active FQDN grants remain
```

第一次呼叫 egress allow API 時，Gateway 才補上 CoreDNS rule 與指定 FQDN rule。
只要仍有 active FQDN grant，就必須持續允許 CoreDNS，否則 FQDN 動態解析與
refresh 會失敗。

## 5. Request flow

### 建立 sandbox

```text
Client
  -> Authorization: Bearer tenant-key
  -> Gateway 查 tenant DB
  -> quota check
  -> claim pool / create sandbox
  -> ownership DB transaction
  -> egress reset
  -> OpenSandbox response
```

### 執行 command 或檔案操作

```text
Client request
  -> tenant authentication
  -> ownership check
  -> scope check
  -> OpenSandbox proxy
  -> stream response
  -> update last_activity_at / metrics
```

### 回收 sandbox

```text
DELETE / TTL expiry / pool release
  -> revoke all active egress grants
  -> reset egress policy
  -> release sandbox to pool or delete it
  -> mark ownership released
  -> emit audit event
```

## 6. Tenant metrics

Gateway 是最可靠的 tenant metrics 邊界，因為 request 進入時已經完成 tenant
authentication。建議提供：

```text
opensandbox_gateway_requests_total{tenant,method,route,status}
opensandbox_gateway_sandboxes_created_total{tenant}
opensandbox_gateway_sandboxes_deleted_total{tenant}
opensandbox_gateway_active_sandboxes{tenant}
opensandbox_gateway_commands_total{tenant}
opensandbox_gateway_uploaded_bytes_total{tenant}
opensandbox_gateway_downloaded_bytes_total{tenant}
opensandbox_gateway_quota_rejections_total{tenant}
```

OpenSandbox Server 原生 metrics 不會自動知道 tenant。若需要 tenant 維度的
CPU、memory、Pod churn，應透過 `sandbox_id -> tenant_id` ownership mapping，
把 Gateway metadata 與 Kubernetes metrics 做 recording rule 或額外 exporter
關聯。不要直接把任意 request path 或 sandbox ID 當成 Prometheus label，避免
高 cardinality。

## 7. Store 選擇

### SQLite

適合目前的單一 Gateway、小型 cluster 與 prototype。需要 PVC，並使用 transaction
保護 tenant 與 ownership 狀態。若未來 Gateway replicas 大於一個，應改成 shared
database 或使用 leader/locking 設計。

### Vault

適合 production tenant credential、key rotation 與多副本 Gateway。Gateway 透過
Kubernetes auth 取得短期 Vault token，使用短 cache 讀取 tenant records；Vault
資料變更不需要重啟 Gateway。

### ConfigMap

適合 development 或唯讀設定快照。Gateway 可監看檔案變更並 reload，但不適合
保存明文 tenant key，也不適合 ownership、egress grant 或高頻 audit state。

建議的演進順序：

```text
SQLite + PVC
  -> PostgreSQL / managed database
  -> Vault 保存 credential，DB 保存 operational state
```

## 8. 目前部署邊界

- Gateway 對外提供 tenant-aware API。
- OpenSandbox Server 保持 ClusterIP-only。
- Gateway Service 使用 private ClusterIP 與 NodePort。
- Gateway metrics 由 Prometheus ServiceMonitor scrape。
- Grafana 依 `tenant` label 顯示 API、session、command 與 transfer usage。
- OpenSandbox Server 的 server credential 不會下發給 tenant。

## 9. 重要安全原則

1. tenant key 只顯示一次，遺失就 rotate，不提供明文查詢。
2. egress reset 失敗時不得交付 warm-pool sandbox。
3. 不讓外部 client 取得 Kubernetes API 權限。
4. 任何 sandbox 操作都必須同時通過 tenant authentication 與 ownership check。
5. Gateway DB、Prometheus 與 audit log 不應保存 command secret 或檔案內容。
6. Production 應加入 TLS、rate limit、per-tenant quota、DB backup 與 key rotation。
