# OpenSandbox Tenant Server 架構

## 1. 目標

OpenSandbox Tenant Server 位於外部 client 與 OpenSandbox Server 之間，提供一個不需要
暴露 Kubernetes API credential，也不需要把 OpenSandbox Server key 發給使用者
的多租戶入口。

```text
Client / Agent
     |
     | Kubernetes ServiceAccount token
     v
OpenSandbox Tenant Server ×3
     |  \
     |   \-- TokenReview request + Tenant Server SA token
     |       v
     |     KFA
     |       |
     |       \-- Kubernetes OIDC/API and JWKS
     |
     |-- identity lookup / authorization --> PostgreSQL
     |     (tenant mapping, scope, quota, ownership)
     |
     | one private server credential
     v
OpenSandbox Server
     |
     v
Warm Pool / Sandbox Pods
```

Tenant Server also owns the following business functions: warm-pool claim/reset, egress
policy lifecycle, streaming proxy and tenant-labelled metrics. KFA does not access
PostgreSQL and does not make tenant authorization decisions.

OpenSandbox Server 只負責 sandbox lifecycle 與 runtime 操作；tenant identity、
權限、配額與 audit context 由 Tenant Server 管理。

Tenant Server 不自行簽發、解析或保存 tenant JWT/API key。它把 client 的
ServiceAccount token 交給 KFA 驗證，再用 KFA 回傳的
`cluster/service-account-uid` principal 對應 PostgreSQL tenant record；
namespace 與 ServiceAccount name 作為可讀 metadata 與相容查詢欄位。

Quota admission is transactional. Before calling OpenSandbox, a replica locks
the tenant row, counts allocated ownership plus active reservations, and writes
a short-lived reservation. A successful upstream create converts that capacity
into `sandbox_owners`; failure releases the reservation. Reservations older
than ten minutes are cleaned on the next reservation attempt.

## 2. Tenant Server 必須提供的效果

### Tenant isolation

- 每個 tenant 對應一個或多個 Kubernetes ServiceAccount identity。
- Tenant Server 透過 KFA 驗證 token，不儲存 client token、JWT 或 API key。
- API request 先解析 KFA identity，再執行 scope 與 quota 檢查。
- sandbox 建立後記錄 `sandbox_id -> tenant_id` ownership。
- tenant 只能 list、command、upload、download、delete 自己的 sandbox。
- OpenSandbox Server 的共同 server key 永遠不下發給 client。

### OpenSandbox API compatibility

Tenant Server 對外維持 OpenSandbox `/v1/...` API 形式，並在內部注入 server credential。
可以採用 allowlist，而不是無條件轉發所有路徑：

- sandbox create / list / get / delete
- lifecycle operations
- command proxy
- file upload / download proxy
- 明確拒絕 `/snapshot`、`/snapshots` 與未知 API

Upload、download 與 command output 必須採 streaming，並設定 request body、
response body、timeout 與 concurrency 上限，避免 Tenant Server 自身成為記憶體瓶頸。

## 3. End-to-end workflows

### 3.1 Tenant onboarding 與 identity mapping

Tenant 建立和正常 sandbox request 是兩條不同的權限路徑。管理者只把 admin
credential 提供給內部管理面；一般 client 使用自己的 ServiceAccount token。

```mermaid
sequenceDiagram
    actor Operator
    participant TS as Tenant Server
    participant DB as PostgreSQL
    participant Secret as Secret Manager
    Operator->>TS: POST /admin/tenants
    TS->>DB: INSERT tenant identity + scopes + quota
    DB-->>TS: committed
    Note over TS,DB: future replicas read the same state
    Operator->>TS: disable or update identity mapping
    TS->>DB: update enabled / identity / version
    DB-->>TS: committed
    Note over TS: no Deployment restart; next request uses new state
```

### 3.2 Normal request admission

所有 `/v1/...` request 都先經過相同的 admission pipeline。任何一個檢查失敗都
在呼叫 OpenSandbox 前結束，避免未授權 request 產生 side effect。

```text
request
  |
  +--> parse Bearer ServiceAccount token
  +--> Tenant Server SA calls KFA TokenReview
  +--> load enabled tenant by cluster/service-account-uid
  +--> resolve route -> required scope
  +--> check request size / rate / tenant quota
  +--> for sandbox ID: verify sandbox_ownership(tenant_id, sandbox_id)
  +--> attach request_id and tenant metrics
  +--> allowlisted OpenSandbox proxy with server credential
  +--> stream response and update last_activity_at
```

### 3.2.1 KFA 驗證的完整 request workflow

本節是 Tenant Server authentication path 的實作契約。開發者不應將它理解成
「Tenant Server 啟動時登入一次，之後永久信任 client」；目前的設計是：每一個
需要身份的 API request 都由 Tenant Server 呼叫 KFA，但 KFA 內部使用短期 cache
避免每次都重做完整的 JWT signature/OIDC key 驗證。

#### 參與元件與 credential 邊界

```text
Client / Agent
  - 持有自己的 Kubernetes ServiceAccount token
  - 只把 token 放在對 Tenant Server 的 Authorization header

Tenant Server Pod
  - 使用自己的 projected ServiceAccount token 呼叫 KFA
  - 不保存 client token
  - 不保存 client JWT signing key
  - 不直接呼叫 Kubernetes TokenReview API

KFA
  - 驗證 caller，也就是 Tenant Server ServiceAccount
  - 驗證 TokenReview.spec.token，也就是 client token
  - 對驗證結果做短期 cache
  - 回傳 canonical Kubernetes identity

PostgreSQL
  - 將 KFA identity 對應到 tenant_id
  - 保存 enabled、scope、quota 與 sandbox ownership
  - 不保存 ServiceAccount token
```

其中有兩個不同的 token，不能混淆：

| Token | 放在哪裡 | 用途 |
|---|---|---|
| client token | client request 的 `Authorization` | 識別真正提出 API request 的 ServiceAccount |
| Tenant Server token | Tenant Server Pod 的 projected token | 讓 KFA 知道是哪個受信任服務在要求 TokenReview |

KFA 的 `authorized_clients` 只控制「哪些服務可以呼叫 KFA」。它不代表該 caller
自動取得某個 tenant 的權限；tenant 權限仍由 Tenant Server 查 PostgreSQL 的
identity mapping 決定。

#### 一次正常 API request 的時序

```mermaid
sequenceDiagram
    participant C as Client / Agent
    participant TS as Tenant Server replica
    participant KFA as kube-federated-auth
    participant OIDC as Kubernetes OIDC/JWKS
    participant DB as PostgreSQL
    participant OS as OpenSandbox Server

    C->>TS: GET /v1/sandboxes<br/>Authorization: Bearer client-SA-token
    TS->>TS: parse Bearer token; do not log token
    TS->>KFA: POST TokenReview<br/>Authorization: Bearer tenant-server-SA-token<br/>spec.token = client-SA-token
    KFA->>KFA: authenticate caller identity
    alt KFA cache hit
        KFA-->>TS: cached authenticated identity
    else KFA cache miss
        KFA->>OIDC: fetch/use issuer metadata and JWKS
        KFA->>KFA: verify signature, issuer, expiry and SA claims
        KFA-->>TS: authenticated identity + cluster extra claim
    end
    TS->>DB: SELECT enabled tenant by cluster/service-account-uid
    DB-->>TS: tenant_id, scopes, quota
    TS->>TS: route/scope/quota/ownership admission
    TS->>OS: forward allowlisted request with private server credential
    OS-->>TS: response/stream
    TS-->>C: response/stream; never expose server credential
```

#### Tenant Server 每次 request 的實際處理順序

以 `GET /v1/sandboxes` 為例，程式流程必須保持以下順序：

1. 讀取 `Authorization` header。沒有 `Bearer` token 時直接回傳 HTTP `401`。
2. 將 client token 放入 TokenReview 的 `spec.token`。client token 不寫入 log、metric、DB
   或 response。
3. 讀取 Tenant Server 自己的 projected token。這個 token 是呼叫 KFA 的 caller credential，
   不是 client token。
4. 呼叫 KFA：

   ```http
   POST /apis/authentication.k8s.io/v1/tokenreviews
   Authorization: Bearer <tenant-server-serviceaccount-token>
   Content-Type: application/json
   ```

   ```json
   {
     "apiVersion": "authentication.k8s.io/v1",
     "kind": "TokenReview",
     "spec": {
       "token": "<client-serviceaccount-token>"
     }
   }
   ```

5. 驗證 KFA response：

   - HTTP status 必須是 2xx。
   - `status.authenticated` 必須是 `true`。
   - `status.user.username` 必須符合：
     `system:serviceaccount:<namespace>:<serviceaccount>`。
   - `status.user.extra["authentication.kubernetes.io/cluster-name"]` 必須存在。
   - 不接受缺少 cluster identity 的 response，避免跨叢集 identity 被錯誤合併。

6. 以 `(cluster_name, namespace, service_account)` 查詢 PostgreSQL：

   ```sql
   SELECT tenant_id, scopes, max_concurrent, enabled
   FROM tenants
   WHERE cluster_name = $1
     AND namespace = $2
     AND service_account = $3
     AND enabled = true;
   ```

7. tenant mapping 不存在或 `enabled=false` 時回傳 HTTP `403`。這和無效 token 的
   HTTP `401` 必須區分：

   - `401`：token 缺失、KFA 無法驗證、token expired、caller 未被 KFA 授權。
   - `403`：token 身份有效，但沒有對應的 enabled tenant 或缺少 scope。

8. 對 sandbox-specific API，再查 `sandbox_owners` 確認：

   ```sql
   sandbox_owners.sandbox_id = request.sandbox_id
   AND sandbox_owners.tenant_id = authenticated_tenant_id
   AND allocation_state = 'allocated'
   ```

9. 所有 admission check 通過後，才把 request 轉送給 OpenSandbox Server，並在 server-side
   request 加入內部 `OPEN-SANDBOX-API-KEY`。client 的 `Authorization` header 不得轉送。

10. response 回傳前記錄 status、latency、tenant label 與 bytes；不得記錄 token、檔案內容、
    command secret 或完整 Authorization header。

#### KFA cache 的命中與未命中

目前 KFA 設定如下：

```yaml
cache:
  ttl: 30          # authenticated result cache, seconds
  negative_ttl: 10 # rejected/unauthenticated result cache, seconds
  max_entries: 1000
```

因此「每次 request 都呼叫 KFA」與「每次 request 都重新做完整 cryptographic verification」
是兩件不同的事：

```text
Request 1
  Tenant Server -> KFA
  KFA cache miss -> OIDC/JWKS verification -> cache result -> response

Request 2..N within 30 seconds, same token
  Tenant Server -> KFA
  KFA cache hit -> response without repeating full verification

After 30 seconds, or cache eviction
  Tenant Server -> KFA
  KFA cache miss -> re-verify token -> refresh cache
```

無效 token 也會短暫 cache：

```text
invalid token request
  -> KFA verifies/rejects
  -> negative result cached for 10 seconds
  -> repeated same invalid token receives fast rejection
```

KFA cache 不會讓 PostgreSQL tenant authorization 被 cache。每個成功的 request 仍然會
在 Tenant Server 查詢 enabled tenant、scope、quota 與 ownership；因此 operator 停用
tenant 後，不需要等待 KFA cache expiry 才能阻止 tenant access。只有「該 ServiceAccount
token 是否有效、它代表哪個 Kubernetes identity」由 KFA 短期 cache 控制。

#### Token expiration 與撤銷行為

ServiceAccount token 是有 expiration 的 credential。Token expiration 不是由 Tenant
Server 自己延長，也不應把 token 存在 PostgreSQL 或 application memory 中。

| 狀況 | 行為 |
|---|---|
| token 尚未 expired，KFA cache miss | KFA 驗證成功並建立短期 cache |
| token 尚未 expired，KFA cache hit | KFA 回傳 cache identity |
| token expired，KFA cache miss | KFA reject，Tenant Server 回 HTTP 401 |
| ServiceAccount 被刪除或 token invalidated | cache 到期或 miss 後被拒絕 |
| tenant `enabled=false` | token 可能仍是有效，但 Tenant Server 回 HTTP 403 |
| scope 不包含 route 所需權限 | identity 有效，但 Tenant Server 回 HTTP 403 |

因此 TTL 的安全取捨是：KFA `cache.ttl` 越短，ServiceAccount revoke 的反應越快，
但 KFA 的驗證與 OIDC/JWKS 工作量越高。目前 30 秒是 lab 的短 cache 設定；production
應依照 token TTL、撤銷需求與 KFA QPS capacity 重新壓測，不應任意改成數小時。

#### KFA failure matrix

| Failure point | Tenant Server response | 是否呼叫 OpenSandbox | 建議 metric/log |
|---|---:|---:|---|
| Authorization header missing | 401 | 否 | `auth_missing` |
| KFA DNS/connection timeout | 401 或受控的 503 policy | 否 | `kfa_unavailable` |
| KFA caller 不在 `authorized_clients` | 401/403 | 否 | `kfa_caller_denied` |
| client token invalid/expired | 401 | 否 | `client_token_rejected` |
| KFA response 缺 cluster identity | 401 | 否 | `kfa_identity_malformed` |
| identity 沒有 tenant mapping | 403 | 否 | `tenant_mapping_missing` |
| tenant disabled | 403 | 否 | `tenant_disabled` |
| required scope missing | 403 | 否 | `scope_denied` |
| ownership 不符合 | 404 | 否 | `ownership_denied` |
| OpenSandbox upstream unavailable | 502 | 已通過 admission | `upstream_unavailable` |

任何 KFA、tenant mapping、scope 或 ownership failure 都必須發生在 OpenSandbox side
effect 之前。尤其是 create、command、upload 與 egress policy API，不能先建立資源
再補做身份驗證。

#### 多副本下的 request 行為

每個 Tenant Server replica 都同時依賴 KFA endpoint 與 PostgreSQL Service，但兩者
不是 KFA → PostgreSQL 的串接關係。KFA 只負責把 token 轉成已驗證的 Kubernetes
identity；Tenant Server 收到 identity 後，才自行查 PostgreSQL 執行 tenant
authorization：

```text
                              ┌──> KFA ──> Kubernetes OIDC/API
Request A -> Tenant Server ───┤
                              └──> PostgreSQL identity/tenant lookup
                                      │
                                      └──> OpenSandbox admission/proxy

Request B -> Tenant Server replica 2
                              ├──> KFA
                              └──> PostgreSQL

Request C -> Tenant Server replica 3
                              ├──> KFA
                              └──> PostgreSQL
```

對單一 request 而言，實際時序是：

```text
Client
  -> Tenant Server
  -> KFA TokenReview
  <- verified identity
  -> PostgreSQL identity/tenant lookup
  -> scope/quota/ownership admission
  -> OpenSandbox Server
```

因此 PostgreSQL 不會被 KFA 呼叫；KFA 也不知道 `tenant_id`、scope、quota 或
sandbox ownership。這些都是 Tenant Server 在取得 KFA identity 後才執行的業務授權。

Tenant Server 不假設 request 一定回到相同 replica，也不使用 local memory 來保存
tenant mapping 或 ownership。KFA cache 位於 KFA instance；如果未來 KFA 擴成多副本，
每個 KFA replica 可以有自己的短期 cache，正確性仍由每次 KFA 驗證與 PostgreSQL
authorization 維持，不能依賴 cache 來保存長期狀態。

#### Admin API workflow

Admin API 也採用 KFA，但它不查一般 tenant mapping，而是額外比對
`TENANT_SERVER_ADMIN_IDENTITIES`：

```text
Operator ServiceAccount token
  -> Tenant Server
  -> KFA TokenReview
  -> identity == configured admin identity?
       no  -> 403
       yes -> allow POST/GET/DELETE /admin/tenants
```

建立 tenant 時，admin 必須明確提交要被信任的 ServiceAccount identity：

```json
{
  "tenant_id": "team-a",
  "cluster_name": "local-cluster",
  "namespace": "team-a",
  "service_account": "runner",
  "scopes": ["sandbox:create", "sandbox:read", "sandbox:command", "sandbox:files"],
  "max_concurrent_sandboxes": 3
}
```

這個 API 不會回傳 tenant key，也不會要求 client 產生 JWT。新增 identity mapping
後，所有 Tenant Server replicas 下一次查 PostgreSQL 時立即使用新設定，不需要 rollout
restart。停用 mapping 也同理。

### 3.3 Warm-pool claim、reset 與交付

warm pool 的重點不是單純預先建立 Pod，而是每次 claim 前都要消除前一個 tenant
留下的 ownership、檔案與 egress 狀態。claim、reset、ownership commit 應具有可重試
的狀態機；同一個 request 重送時不能產生兩筆 active ownership。

```mermaid
flowchart TD
    A[Create request] --> B{tenant/scope/quota valid?}
    B -- no --> X[Reject without sandbox]
    B -- yes --> C{available warm sandbox?}
    C -- yes --> D[Claim with DB lease]
    C -- no --> E[Create new sandbox]
    D --> F[quarantine + reset old state]
    E --> F
    F --> G[default deny baseline]
    G --> H{reset verified?}
    H -- no --> I[mark quarantine and audit failure]
    H -- yes --> J[write sandbox ownership]
    J --> K[return sandbox session]
```

實際的安全順序是：

1. 先取得 tenant quota 與 pool lease，避免多副本同時認領同一個 sandbox。
2. 將 sandbox 標記為 `quarantine`，暫時不讓 client 使用。
3. 清除前一個 tenant 的 egress grants、DNS 規則、session metadata 與 workspace。
4. 套用 default-deny baseline；預設不允許 DNS 或外部 egress。
5. 驗證 reset 結果，再寫入新的 `sandbox_ownership` 與 `allocation_state=allocated`。
6. 若任一步失敗，保留 quarantine 狀態並由補償工作重試，不把半清理的 sandbox 交付。

### 3.4 Egress request 與 FQDN lifecycle

Sandbox 初始不具備 DNS 流量。Tenant Server 先驗證 tenant 是否擁有 sandbox，再驗證
FQDN 格式、port、租戶 allowlist 與 grant TTL，最後才建立可追蹤的 policy change。

```mermaid
sequenceDiagram
    participant Agent
    participant TS as Tenant Server
    participant DB as PostgreSQL
    participant NP as Egress Policy Controller
    participant DNS as CoreDNS
    Agent->>TS: POST /sessions/{id}/egress {fqdn, ports}
    TS->>DB: verify ownership + insert requested grant
    TS->>NP: apply DNS + FQDN allow rule
    NP-->>TS: policy applied / rejected
    alt applied
        TS->>DB: state=active, expires_at
        TS-->>Agent: grant active
        Agent->>DNS: resolve approved FQDN
    else rejected
        TS->>DB: state=revoked + audit failure
        TS-->>Agent: error
    end
```

規則回收不依賴 client 是否正常關閉網頁：DELETE、TTL expiry、server restart recovery
與 pool release 都會執行同一個 idempotent revoke/reset 流程。當該 sandbox 已沒有
active FQDN grant 時，DNS allow 也一併移除。

### 3.5 Command、upload、download 的 streaming flow

Tenant Server 不把大型檔案或長時間 command output 全部讀進 memory。每一個 stream
都要套用 body limit、idle timeout、overall timeout、client disconnect cancellation
與 concurrency quota。

```text
Agent
  -> authenticated command/upload/download request
  -> Tenant Server admission + ownership check
  -> OpenSandbox stream
  -> copy chunks while enforcing limits
  -> client disconnect cancels upstream context
  -> record bytes / duration / status, never record content
```

### 3.6 TTL、release 與故障補償

```mermaid
stateDiagram-v2
    [*] --> available
    available --> allocated: claim lease
    allocated --> allocated: command/file activity extends last_activity_at
    allocated --> releasing: DELETE or TTL expired
    releasing --> available: reset verified and pool retained
    releasing --> deleted: pool policy deletes sandbox
    allocated --> quarantine: reset or policy failure
    quarantine --> releasing: retry succeeds
    quarantine --> quarantine: retry/backoff
```

TTL worker 必須以 PostgreSQL row lock 或 lease version 搶工作；因此三個 Tenant Server
replica 同時掃描 expired rows 時只有一個可以執行 release。所有 transition 都要有
audit event，讓 operator 能分辨「正常 TTL 回收」與「因 egress reset 失敗而隔離」。

### 3.7 Multi-replica request 與資料流

```text
Client
  -> NodePort / private node IP
       +--> Tenant Server replica 1 --+
       +--> Tenant Server replica 2 ---+--> PostgreSQL read-write Service
       +--> Tenant Server replica 3 --+          |
                                             ownership / tenant / grants
                                                    |
                                             OpenSandbox Server
```

Tenant Server 不使用本地檔案保存租戶狀態，也不把 request sticky session 當成一致性
機制。任何 replica 都能處理下一個 request；一致性由 PostgreSQL transaction、ownership
constraint 與 lease version 提供。

## 4. DB 的責任

Tenant Server 需要一個 durable state store。這個 DB 不保存 client credential，而是保存
跨請求需要的 ownership、egress、quota 與 audit 狀態。

### Tenant

```text
tenant_id
cluster_name
namespace
service_account
enabled
scopes
max_concurrent_sandboxes
max_request_bytes
created_at
updated_at
display_name
last_authenticated_at
status_reason
```

`cluster_name`、`namespace`、`service_account` 組成 tenant identity。停用或
變更 identity 不需要重啟 Tenant Server，之後的新 request 立即依照資料庫狀態
被拒絕或重新映射。

Tenant 的資料分成四類：身份（`tenant_id`、`cluster_name`、`namespace`、`service_account`）、
credential 狀態（由 KFA 與 Kubernetes ServiceAccount 管理，Tenant Server 不保存明文 token）、
授權與資源限制（`scopes`、sandbox/concurrency、request/file bytes quota），以及
營運狀態（enabled、建立/更新/最後驗證時間與停用原因）。ServiceAccount token
由 Kubernetes projected token 機制提供與輪替。

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

這張表用來阻止 tenant A 操作 tenant B 的 sandbox，也讓 Tenant Server 能將
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
quota rejection 與被拒絕的 API route，但不要將 ServiceAccount token、檔案內容或 command
secret 寫入 audit log。

## 5. Warm pool 與 egress 的整合

Warm pool 的 Pod 可能會被不同 tenant 依序使用，因此 claim 不是單純把一個
sandbox ID 回傳給 client，而是一個需要 transaction 與安全清理的流程。

```text
1. Tenant Server 收到 create request
2. 驗證 tenant、scope 與 quota
3. 認領 warm-pool sandbox；沒有可用資源才建立新的 sandbox
4. 建立 sandbox ownership record
5. reset egress policy
6. 套用 baseline policy：default deny、必要的 control-plane access
7. 確認 reset 成功後才回傳 sandbox
```

如果 egress reset 失敗，Tenant Server 必須將 sandbox 標記為 `quarantine`，不能交付
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

第一次呼叫 egress allow API 時，Tenant Server 才補上 CoreDNS rule 與指定 FQDN rule。
只要仍有 active FQDN grant，就必須持續允許 CoreDNS，否則 FQDN 動態解析與
refresh 會失敗。

## 6. Request flow

### 建立 sandbox

```text
Client
  -> Authorization: Bearer tenant-key
  -> Tenant Server 查 tenant DB
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

## 7. Tenant metrics

Tenant Server 是最可靠的 tenant metrics 邊界，因為 request 進入時已經完成 tenant
authentication。建議提供：

```text
opensandbox_tenant_server_requests_total{tenant,method,route,status}
opensandbox_tenant_server_sandboxes_created_total{tenant}
opensandbox_tenant_server_sandboxes_deleted_total{tenant}
opensandbox_tenant_server_active_sandboxes{tenant}
opensandbox_tenant_server_commands_total{tenant}
opensandbox_tenant_server_uploaded_bytes_total{tenant}
opensandbox_tenant_server_downloaded_bytes_total{tenant}
opensandbox_tenant_server_quota_rejections_total{tenant}
```

OpenSandbox Server 原生 metrics 不會自動知道 tenant。若需要 tenant 維度的
CPU、memory、Pod churn，應透過 `sandbox_id -> tenant_id` ownership mapping，
把 Tenant Server metadata 與 Kubernetes metrics 做 recording rule 或額外 exporter
關聯。不要直接把任意 request path 或 sandbox ID 當成 Prometheus label，避免
高 cardinality。

## 8. Store 選擇

### PostgreSQL HA

正式多副本架構使用 PostgreSQL HA，而不是三個互相獨立的 PostgreSQL Pod。
建議使用 CloudNativePG 管理三個 PostgreSQL instances：一個 primary、兩個
replicas，由 operator 提供 read-write Service、failover、replication 與各自的
PVC。Tenant Server 永遠連線 operator 管理的 read-write Service，不直接連特定
PostgreSQL Pod。

```text
OpenSandbox Tenant Server ×3
          |
          v
PostgreSQL read-write Service
          |
   PostgreSQL HA ×3
   primary + 2 replicas
```

租戶與 ownership state 都必須寫入 PostgreSQL；Tenant Server 不依賴本地檔案或
本地 PVC。資料庫故障轉移時，connection pool 應使用 retry/backoff 重新建立連線。

目前環境已先部署 PostgreSQL shared state，正式 HA migration 應以 CloudNativePG
Cluster resource 取代單一 PostgreSQL Deployment。CloudNativePG 官方也建議
應用程式連接 operator 管理的 Service，而不是固定某個資料庫 instance。

### SQLite

只適合單一 Tenant Server、小型 cluster 與 prototype。需要 PVC，並使用 transaction
保護 tenant 與 ownership 狀態。若未來 Tenant Server replicas 大於一個，應改成 shared
database 或使用 leader/locking 設計。

### Vault

適合 production tenant identity 與多副本 Tenant Server。Tenant Server 透過
Kubernetes auth 取得短期 Vault token，使用短 cache 讀取 tenant records；Vault
資料變更不需要重啟 Tenant Server。

### ConfigMap

適合 development 或唯讀設定快照。Tenant Server 可監看檔案變更並 reload，但不適合
保存 client token，也不適合 ownership、egress grant 或高頻 audit state。

建議的演進順序：

```text
SQLite + PVC
  -> PostgreSQL shared state
  -> PostgreSQL HA ×3 / managed PostgreSQL
  -> Vault 保存 credential，PostgreSQL 保存 operational state
```

## 9. 目前部署邊界

- Go OpenSandbox Tenant Server ×3 對外提供 tenant-aware API。
- OpenSandbox Server 保持 ClusterIP-only。
- Tenant Server 使用正常 Pod networking，內部透過 ClusterIP/Service DNS 溝通；測試環境可保留 NodePort `30081`，正式環境應由 HTTPS ingress 提供入口。
- Tenant Server metrics 由 Prometheus ServiceMonitor scrape。
- Grafana 依 `tenant` label 顯示 API、session、command 與 transfer usage。
- OpenSandbox Server 的 server credential 不會下發給 tenant。

## 10. 重要安全原則

1. Tenant identity 由 Kubernetes ServiceAccount 與 KFA 管理，不在 Tenant Server 產生或保存 key。
2. egress reset 失敗時不得交付 warm-pool sandbox。
3. 不讓外部 client 取得 Kubernetes API 權限。
4. 任何 sandbox 操作都必須同時通過 tenant authentication 與 ownership check。
5. Tenant Server DB、Prometheus 與 audit log 不應保存 command secret 或檔案內容。
6. Production 應加入 TLS、rate limit、per-tenant quota、DB backup 與 ServiceAccount/KFA rotation。

## 11. 測試與驗收 workflow

每次 Go code、Docker image、Kubernetes manifest、DB schema、authentication 或
egress policy 變更，都依序執行：

```text
go test -race -count=1 ./...
  -> build immutable image
  -> import image to every node
  -> kubectl apply + rollout status
  -> tenant-server-smoke.sh
  -> optional CHECK_K8S=1 CHECK_PROMETHEUS=1
  -> inspect Grafana / Prometheus target
```

目前 smoke test 會驗證 health、三副本、每個 private node endpoint、metrics tenant
label、unauthenticated rejection、temporary tenant lifecycle、disabled tenant rejection、
snapshot deny 與 Prometheus 三個 target；並在成功或失敗時清理 temporary tenant。
不會創建 sandbox，因此可以在 production-like 環境反覆執行。真正涉及 sandbox 的
integration test 必須使用專用測試 tenant 與 disposable pool，完成後確認 ownership、
egress grant、Pod 與檔案都已清理。

## 12. 實作檔案

- Go Tenant Server：[main.go](tenant-server-go/main.go)
- Go module：[go.mod](tenant-server-go/go.mod)
- immutable runtime image：[Dockerfile](tenant-server-go/Dockerfile)
- PostgreSQL HA target：[postgres-ha.yaml](k8s/postgres-ha.yaml)
- Tenant Server deployment：[tenant-server.yaml](k8s/tenant-server.yaml)
