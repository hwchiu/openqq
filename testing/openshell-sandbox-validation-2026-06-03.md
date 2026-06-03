# OpenShell Sandbox 特性驗證報告

日期: 2026-06-03  
環境: Azure `eastus` / Terraform 建立之 3-node `k3s` / OpenShell `0.0.53`

## 目的

這份報告只驗證 `OpenShell sandbox` 自己的特性，不再把 Kubernetes 原生能力當成主要證據。

本次要回答的問題是:

1. OpenShell sandbox 是否真的有自己獨特的 runtime enforcement
2. 這些 enforcement 是否不是普通 Pod / `NetworkPolicy` / PVC 就能直接等價替代
3. 我們目前這個 `k3s` 叢集要滿足什麼條件，OpenShell sandbox 才能真正運作

## 先講結論

有，`OpenShell sandbox` 確實有自己獨特的特性，而且這次已經做出實測。

真正驗證到的特性有:

1. OpenShell 不是單純「幫你開一個 Pod」
2. 它在 sandbox 內部建立自己的網路命名空間與代理路徑
3. 它對 child process 套用自己的 filesystem sandbox
4. 它對 egress 採取預設拒絕
5. 它可以做到「指定 binary 才能連某個 endpoint」
6. 它可以做到 L7 method/path 級別控制
7. policy 可以熱更新，不需要重建 sandbox Pod

這些都不是單靠 Kubernetes `NetworkPolicy` 可以等價做到的。  
`NetworkPolicy` 只能管 Pod 到 Pod / CIDR / port 的網路層；它不能表達:

- 只有 `/usr/bin/curl` 可以出去
- `python3` 不可以出去
- `GET /zen` 可以，但 `POST /repos/.../issues` 不可以
- `/tmp` 可寫，但 `/var/tmp` 不可寫
- sandbox child process 不能直接列出 `/`

## 測試前發現的關鍵問題

在目前這個 `k3s` 叢集上，OpenShell sandbox 一開始其實無法正常啟動。

實際錯誤:

```text
Error:   × Network namespace creation failed and proxy mode requires isolation.
  │ Ensure CAP_NET_ADMIN and CAP_SYS_ADMIN are available and iproute2 is
  │ installed. Error: /usr/sbin/ip netns add sandbox-<id> failed: mount
  │ --make-shared /run/netns failed: Permission denied
```

這個錯誤非常重要，因為它反而證明了一件事:

- OpenShell sandbox 的特殊性之一，就是它依賴自己的 netns / proxy enforcement
- 它不是普通 container 直接跑起來就算完成
- 如果底層 Kubernetes sandbox 權限不足，OpenShell 的真正 enforcement 根本不會生效

### 本次為了完成驗證所做的調整

我把 `proof-demo` 這個 OpenShell sandbox 對應的 `Sandbox` CRD 改成 `privileged: true`，再重建 Pod，才讓它進入 `Ready`。

這表示目前 repo 內的 OpenShell Kubernetes 佈署還不算完整可重現。  
現況是:

1. Gateway 可以正常跑
2. Sandbox workload 建得出來
3. 但要讓真正的 OpenShell sandbox enforcement 運作，還需要補齊 Kubernetes 側的權限模型

## 驗證流程

測試 sandbox 名稱: `proof-demo`

### 階段 1: 不套自訂 policy，驗證預設 sandbox 行為

進入 sandbox 後，實際執行了下列動作:

```sh
id
pwd
ls /
touch /tmp/os-ok
touch /var/tmp/os-deny
curl -sS https://api.github.com/zen
```

### 實測結果

```text
uid=998(sandbox) gid=998(sandbox) groups=998(sandbox)
/sandbox
ls: cannot open directory '/': Permission denied
TMP_OK
touch: cannot touch '/var/tmp/os-deny': Permission denied
curl: (56) CONNECT tunnel failed, response 403
```

### 這代表什麼

1. child process 實際上不是用 root 身份在跑，而是 `sandbox` 使用者
2. OpenShell 的 filesystem sandbox 已經生效
3. 根目錄列舉被阻擋
4. `/tmp` 可寫，但 `/var/tmp` 不可寫
5. 對外 egress 不是預設放行，而是預設拒絕

這裡最重要的是第 4 與第 5 點。  
它們不是普通 Kubernetes Pod 的預設行為。

## 階段 2: 套入 OpenShell policy，驗證 binary 與 L7 控制

本次套入的 policy 檔在:

- [github_readonly.yaml](/Users/hwchiu/hwchiu/openqq/testing/raw/openshell-sandbox-proof/github_readonly.yaml)

這份 policy 的核心意義是:

1. 只有 `/usr/bin/curl` 可以連 `api.github.com:443`
2. 協定是 `rest`
3. 存取模式是 `read-only`
4. 也就是允許讀取型請求，但不允許寫入型 API 行為

### 套 policy 後的驗證指令

```sh
curl -sS https://api.github.com/zen
python3 - <<'PY'
import urllib.request
print(urllib.request.urlopen('https://api.github.com/zen', timeout=10).read().decode())
PY
curl -sS -X POST https://api.github.com/repos/octocat/hello-world/issues -d '{"title":"oops"}'
```

### 實測結果

`curl GET` 成功:

```text
Responsive is better than fast.
```

`python3` 連同一個 GitHub endpoint 失敗:

```text
urllib.error.URLError: <urlopen error Tunnel connection failed: 403 Forbidden>
```

`curl POST` 被 L7 policy 阻擋:

```json
{"binary":"/usr/bin/curl","detail":"POST /repos/octocat/hello-world/issues not permitted by policy","error":"policy_denied","host":"api.github.com","layer":"l7","method":"POST","path":"/repos/octocat/hello-world/issues","policy":"github_api","port":443,"protocol":"rest"}
```

### 這代表什麼

這一段才是真正最有價值的 OpenShell 證據。

因為它證明 OpenShell 可以同時做到:

1. 同一個 hostname / port，不同 binary 有不同結果
2. 同一個 binary，同一個 hostname / port，不同 HTTP method/path 有不同結果

也就是:

- `/usr/bin/curl` + `GET /zen` -> 允許
- `python3` + `GET /zen` -> 拒絕
- `/usr/bin/curl` + `POST /repos/.../issues` -> 拒絕

這種控制粒度不是 Kubernetes `NetworkPolicy` 的能力範圍。

## 階段 3: 驗證 policy 熱更新不重建 Pod

套 policy 前後，我有比對 `proof-demo` Pod UID。

結果:

```text
before: d1aef3ab-d47e-4b18-991d-760f48bd6fec
after:  d1aef3ab-d47e-4b18-991d-760f48bd6fec
```

這代表 policy 生效時，sandbox Pod 沒有被重建。

也就是說，OpenShell 的 policy 是 runtime hot-reload，而不是靠刪 Pod / 重建 Pod 才生效。

## 階段 4: 證明動態 policy 與靜態 policy 的差異

這一段是本次最能說明 `OpenShell` 架構價值的實驗。

我把 policy 再改成第 3 版，唯一重點是:

1. 保留原本允許 `curl` 讀取 GitHub API 的動態 network policy
2. 額外把 `filesystem_policy.read_write` 加上 `/var/tmp`

理論上如果 filesystem 也是動態熱更新，那麼 `/var/tmp` 就應該變成可寫。

### 實測結果

Pod UID 沒變:

```text
after-policy-set pod uid: d1aef3ab-d47e-4b18-991d-760f48bd6fec
```

但 sandbox 內結果是:

```text
touch: cannot touch '/var/tmp/after-static-policy': Permission denied
VARTMP_DENIED
Keep it logically awesome.
```

也就是:

1. `/var/tmp` 仍然不能寫
2. `curl https://api.github.com/zen` 仍然可以成功

### 這代表什麼

這正好對應官方文件描述:

1. `filesystem_policy` 是靜態控制，鎖在 sandbox 建立時
2. `network_policies` 是動態控制，可在 runtime 熱更新

這不是單純「policy server 下發 YAML」而已，而是 OpenShell 把控制分成兩層:

1. 靜態層: supervisor 在 sandbox 啟動時建立 process / filesystem isolation
2. 動態層: gateway 對 live sandbox 下發新的 network policy

## 階段 5: 驗證 sandbox 沒有預設暴露 Kubernetes API token

這一步的目的，是把 OpenShell sandbox 和一般 Kubernetes Pod 的預設曝險面切開。

在 `proof-auto` sandbox 內實測：

```text
K8S_SA_ABSENT
OPENSHELL_BOOTSTRAP_PRESENT
```

這代表：

1. 標準 Kubernetes service account token 並沒有直接暴露給 child process
2. 但 OpenShell 自己仍保留 bootstrap token 路徑，讓 supervisor 去和 gateway 完成 sandbox JWT 的交換

這點很重要，因為它說明 OpenShell 在 Kubernetes 上並不是簡單地把預設 service account 直接塞進 agent 執行環境。

## 階段 6: 把 containerd 路徑的 workaround 產品化

目前 `k3s + containerd` 下，如果沒有額外處理，OpenShell sandbox 會因為 netns 建立失敗而 crash。

因此 repo 已新增：

- [k8s/openshell-sandbox-patcher.yaml](/Users/hwchiu/hwchiu/openqq/k8s/openshell-sandbox-patcher.yaml)
- [scripts/install-openshell-sandbox-patcher.sh](/Users/hwchiu/hwchiu/openqq/scripts/install-openshell-sandbox-patcher.sh)

這個 patcher 會：

1. 監看 `openshell` namespace 中由 OpenShell 管理的 `Sandbox`
2. 自動把 `spec.podTemplate.spec.containers[0].securityContext.privileged=true` 補上去
3. 若現有 Pod 仍是舊的 non-privileged spec，則刪除 Pod，讓 controller 依新 spec 重建

### 產品化驗證結果

我建立了一個全新的 sandbox `proof-auto-...`，不手動 patch。

結果在觀察期間內直接看到：

```text
spec.privileged=true
Sandbox Ready=True
Pod Running
```

這代表至少在目前的 `containerd` lab 上，OpenShell sandbox 的關鍵 workaround 已被自動化，不需要再手動修單一 sandbox。

這個差異非常重要，因為它解釋了:

- 為什麼 OpenShell 不是只有一個 CLI
- 也不是只有一個 CRD controller
- 而是 `gateway + supervisor + sandbox runtime` 一起構成整體安全模型

## Sandbox log 佐證

節錄自 sandbox log:

```text
CONFIG:PROBED Landlock filesystem sandbox available
CONFIG:APPLYING Applying Landlock filesystem sandbox
NET:OPEN DENIED /usr/bin/curl -> api.github.com:443
CONFIG:DETECTED config change detected
CONFIG:LOADED Policy reloaded successfully
NET:OPEN ALLOWED /usr/bin/curl -> api.github.com:443
HTTP:GET ALLOWED GET http://api.github.com:443/zen
NET:OPEN DENIED /sandbox/.uv/python/.../python3.14 -> api.github.com:443
HTTP:POST DENIED POST http://api.github.com:443/repos/octocat/hello-world/issues
```

重點不是 log 文字本身，而是它反映出三件事情:

1. Landlock filesystem sandbox 被探測並套用
2. policy 有被 reload
3. binary 與 L7 deny/allow 都有明確命中紀錄

完整節錄在:

- [sandbox_logs_excerpt.txt](/Users/hwchiu/hwchiu/openqq/testing/raw/openshell-sandbox-proof/sandbox_logs_excerpt.txt)

## 這次能誠實宣稱的事情

現在可以誠實宣稱:

1. OpenShell sandbox 的確有自己獨特的 runtime enforcement
2. 這些 enforcement 不等同於 Kubernetes `NetworkPolicy`
3. 我們已經在實機環境驗證到 filesystem sandbox、default-deny egress、binary allowlist、L7 method/path 控制、policy hot-reload
4. 我們也驗證到 OpenShell 的 static controls 與 dynamic controls 真的分層存在，並且行為不同
5. 我們也驗證到 sandbox child process 沒有直接暴露標準 Kubernetes API token
6. 目前 `containerd` 路徑的 privileged workaround 已被產品化成可重現 patcher

## 這次不能誠實宣稱的事情

還不能宣稱:

1. 目前 repo 的 OpenShell Kubernetes 安裝已經完整產品化
2. 現在這個 `k3s` 佈署不需額外調整就能穩定支援所有 OpenShell sandbox
3. 目前的 Helm values 已經把 sandbox 所需權限模型完整 encode 進去

因為這次要讓 sandbox 真正 ready，仍然需要手動把 `proof-demo` sandbox pod 調成 `privileged`。

## 對 repo 的直接意義

如果後續要把這套環境變成可重現、可交接、不是手修的版本，下一步不是再寫更多比較報告，而是把下面這件事做實:

1. 找出 OpenShell 在 `k3s` / `agent-sandbox` 上的正式權限需求
2. 把 sandbox pod 的權限模型寫進可重現設定
3. 再重新跑一次完全自動化驗證

否則目前只能說:

- 我們已經驗證出 OpenShell sandbox 的特殊性
- 但還沒有把它完整產品化到這個 repo 的 Kubernetes 安裝流程中

## 相關原始資料

- [github_readonly.yaml](/Users/hwchiu/hwchiu/openqq/testing/raw/openshell-sandbox-proof/github_readonly.yaml)
- [github_readonly_plus_vartmp.yaml](/Users/hwchiu/hwchiu/openqq/testing/raw/openshell-sandbox-proof/github_readonly_plus_vartmp.yaml)
- [pod_uid_before.txt](/Users/hwchiu/hwchiu/openqq/testing/raw/openshell-sandbox-proof/pod_uid_before.txt)
- [pod_uid.txt](/Users/hwchiu/hwchiu/openqq/testing/raw/openshell-sandbox-proof/pod_uid.txt)
- [sandbox_status.txt](/Users/hwchiu/hwchiu/openqq/testing/raw/openshell-sandbox-proof/sandbox_status.txt)
- [sandbox_logs_excerpt.txt](/Users/hwchiu/hwchiu/openqq/testing/raw/openshell-sandbox-proof/sandbox_logs_excerpt.txt)
- [bootstrap_error.txt](/Users/hwchiu/hwchiu/openqq/testing/raw/openshell-sandbox-proof/bootstrap_error.txt)
