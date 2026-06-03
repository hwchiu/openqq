# OpenShell on gVisor 驗證報告

日期: 2026-06-03
環境: Azure `eastus` / Terraform 建立之 3-node `k3s` / `containerd` / `RuntimeClass gvisor` / OpenShell `0.0.53`

## 摘要

這次不是只把 runtime 從 `runc` 換成 `gVisor`，而是重跑 OpenShell 驗證，確認哪些安全能力仍然成立、哪些能力在 gVisor 路徑退化。

最重要的結論:

1. `gVisor` 本身已確認真的在跑，不是只有 Kubernetes spec 宣告
2. OpenShell 的 `network_policies`、binary allowlist、L7 method/path 控制、policy hot-reload 在 gVisor 上仍然成立
3. OpenShell 的 `filesystem_policy` 在目前這個組合下沒有成立
4. 退化證據不是推測，而是 sandbox log 直接回報 `Landlock Filesystem Sandbox Unavailable`
5. 所以目前不能把 `k3s + gVisor + OpenShell` 說成單向升級，它是「底層隔離增強，但 OpenShell filesystem enforcement 退化」

## 環境狀態

`kubectl get nodes -o wide` 實際結果:

```text
NAME       STATUS   ROLES           VERSION        CONTAINER-RUNTIME
cp-0       Ready    control-plane   v1.35.5+k3s1   containerd://2.2.3-k3s1
worker-1   Ready    <none>          v1.35.5+k3s1   containerd://2.2.3-k3s1
worker-2   Ready    <none>          v1.35.5+k3s1   containerd://2.2.3-k3s1
```

`RuntimeClass`:

```text
gvisor -> handler: runsc
```

## 證明 gVisor 真的在跑

`runtimeClassName: gvisor` 的 probe pod 實際輸出:

```text
4.19.0-gvisor
Linux version 4.19.0-gvisor #1 SMP Sun Jan 10 15:06:54 PST 2016
gVisor-probe-OK
```

這一點很重要，因為它證明我們不是只在 YAML 裡寫 `runtimeClassName: gvisor`，而是真的由 `runsc` 啟動。

## OpenShell sandbox 建立路徑

本次驗證腳本建立的 sandbox 名稱是:

- `verify-1780497002`

對應證據在:

- `testing/raw/verify-1780497002/`

這個 sandbox 建立後，`Sandbox` CR 的核心欄位已被 patcher 改成:

- `runtimeClassName: gvisor`
- `securityContext.privileged: true`

這證明 `openshell-sandbox-patcher-gvisor` 確實在作用。

## 驗證結果

### 1. 預設出口封鎖: 成立

檔案:

- `testing/raw/verify-1780497002/default-egress.txt`

內容:

```text
curl: (56) CONNECT tunnel failed, response 403
```

結論:

- OpenShell 預設 deny egress 在 gVisor 上仍然成立
- 這表示 supervisor 的 proxy / netns 管理沒有因為換 runtime 而失效

### 2. filesystem / Landlock: 不成立

檔案:

- `testing/raw/verify-1780497002/filesystem.txt`
- `testing/raw/verify-1780497002/static-baseline.txt`
- `testing/raw/verify-1780497002/sandbox-logs.txt`

`filesystem.txt`:

```text
TMP_OK
VARTMP_OK
```

`static-baseline.txt` 顯示可列出根目錄內容，而不是像 runc 組那樣被拒絕。

`sandbox-logs.txt` 直接出現:

```text
FINDING:UNKNOWN [HIGH] "Landlock Filesystem Sandbox Unavailable"
```

結論:

- `filesystem_policy` 在這條 gVisor 路徑沒有成立
- 這不是 policy 沒下發，而是 Landlock 本身不可用
- 對外說明時必須誠實寫成「filesystem enforcement degraded」

### 3. curl GET 放行: 成立

檔案:

- `testing/raw/verify-1780497002/curl-get.txt`

內容:

```text
Favor focus over features.
```

結論:

- `curl` 這個被允許的 binary 可以對 `api.github.com:443` 發送 GET
- OpenShell 的 allowlist 與 L7 read-only policy 在 gVisor 上成立

### 4. python3 GET 拒絕: 成立

檔案:

- `testing/raw/verify-1780497002/python-get.txt`

核心結果:

```text
urllib.error.URLError: <urlopen error Tunnel connection failed: 403 Forbidden>
```

結論:

- 同一個 endpoint，`python3` 仍被拒絕
- 代表 OpenShell 的 binary 級控制不依賴 runc

### 5. curl POST 拒絕: 成立

檔案:

- `testing/raw/verify-1780497002/curl-post.txt`

內容:

```json
{"binary":"/usr/bin/curl","detail":"POST /repos/octocat/hello-world/issues not permitted by policy","error":"policy_denied","host":"api.github.com","layer":"l7","method":"POST","path":"/repos/octocat/hello-world/issues","policy":"github_api","port":443,"protocol":"rest"}
```

結論:

- 同一個 binary、同一個 host/port，method/path 仍可被細粒度拒絕
- L7 policy engine 在 gVisor 上成立

### 6. policy hot-reload: 成立

檔案:

- `testing/raw/verify-1780497002/pod_uid_before.txt`
- `testing/raw/verify-1780497002/pod_uid_after.txt`

內容:

```text
fbf7b80c-f6f2-4930-a1d3-edbcbad9eb71
fbf7b80c-f6f2-4930-a1d3-edbcbad9eb71
```

結論:

- policy 套用前後 Pod UID 相同
- OpenShell 的 runtime hot-reload 不依賴 Pod 重建

### 7. gVisor patcher: 成立

證據:

- `openshell-sandbox-patcher-gvisor` deployment running
- Sandbox CR 顯示 `runtimeClassName: gvisor`
- Sandbox CR 顯示 container `privileged: true`

結論:

- 在 `k3s` 上，這個 patcher 是必要條件
- 沒有它，OpenShell sandbox 不會落到 gVisor runtime，也無法穩定建立 netns

## 核心日誌判讀

`sandbox-logs.txt` 裡面最有價值的幾段是:

### 網路層成立

```text
CONFIG:CREATED [INFO] Network namespace created [ns:sandbox-43e485fc host_ip:10.200.0.1 sandbox_ip:10.200.0.2]
NET:LISTEN [INFO] 10.200.0.1:3128
```

這證明:

- OpenShell 自己的 proxy 與 netns enforcement 還在
- gVisor 沒有讓這一層直接失效

### filesystem 層退化

```text
FINDING:UNKNOWN [HIGH] "Landlock Filesystem Sandbox Unavailable"
```

這證明:

- 不是單純 `/var/tmp` 測試碰巧通過
- supervisor 自己就知道 Landlock 不可用

### L7 層成立

```text
HTTP:GET [INFO] ALLOWED GET http://api.github.com:443/zen [policy:github_api engine:l7]
HTTP:POST [MED] DENIED POST http://api.github.com:443/repos/octocat/hello-world/issues [policy:github_api engine:l7]
```

這證明:

- method/path 級別的 policy engine 仍在工作

## 與 runc 基準組的真正差異

### runc 組

成立:

1. 預設 deny egress
2. binary allowlist
3. L7 method/path 控制
4. policy hot-reload
5. Landlock filesystem sandbox

### gVisor 組

成立:

1. 預設 deny egress
2. binary allowlist
3. L7 method/path 控制
4. policy hot-reload
5. gVisor 自身的 syscall / kernel 邊界

退化:

1. Landlock filesystem sandbox

## 正確的對外說法

可以說:

- 我們已把 Azure 測試環境切到 `k3s + gVisor`
- OpenShell 在 gVisor 上仍可提供 network 與 L7 行為治理
- gVisor runtime 也已被實測確認
- 但目前 OpenShell 的 filesystem policy 在這組合下不可用

不應該說:

- gVisor 版 OpenShell 全面比 runc 版更安全
- OpenShell 所有功能在 gVisor 上完全等價

## 後續建議

1. 找出 OpenShell 與 gVisor 在 Landlock 路徑上的相容性限制
2. 如果 filesystem enforcement 是必要需求，先保留 runc 組作為可用基準
3. 如果目標是更強 kernel 邊界，則要把 gVisor 組與 runc 組當成兩種不同防禦取向，而不是單一升級路徑
