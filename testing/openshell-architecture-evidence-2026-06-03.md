# OpenShell Driver / Supervisor / Sandbox 證據報告

日期: 2026-06-03

這份文件只做一件事：把 `driver`、`supervisor`、`agent-sandbox`、`OpenShell sandbox` 這些概念，對應到目前叢集上的實際證據。

## 1. Kubernetes driver 真的存在

### 證據 1: Gateway ConfigMap

- [openshell-configmap.yaml](/Users/hwchiu/hwchiu/openqq/testing/raw/architecture-evidence/openshell-configmap.yaml)

裡面明確存在：

```toml
[openshell.drivers.kubernetes]
grpc_endpoint              = "http://openshell.openshell.svc.cluster.local:8080"
service_account_name       = "openshell-sandbox"
supervisor_sideload_method = "image-volume"
```

這證明：

1. 現在這個 OpenShell gateway 的 compute driver 是 Kubernetes
2. 它使用 `openshell-sandbox` service account
3. 它知道 supervisor 要怎麼 side-load 到 sandbox pod

### 證據 2: Gateway log

- [openshell-driver-log.txt](/Users/hwchiu/hwchiu/openqq/testing/raw/architecture-evidence/openshell-driver-log.txt)

裡面可見：

1. `openshell_driver_kubernetes::driver`
2. `Creating sandbox in Kubernetes`
3. `Listing sandboxes from Kubernetes`

這不是文件描述，而是目前 cluster 的實際 runtime log。

## 2. agent-sandbox 真的存在，而且在承載 OpenShell sandbox

### 證據 1: controller pod

- [agent-sandbox-controller-pod.yaml](/Users/hwchiu/hwchiu/openqq/testing/raw/architecture-evidence/agent-sandbox-controller-pod.yaml)

這是目前 cluster 裡的 `agent-sandbox` controller。

### 證據 2: OpenShell 建出來的是 `Sandbox` CR

- [proof-auto-sandbox.yaml](/Users/hwchiu/hwchiu/openqq/testing/raw/architecture-evidence/proof-auto-sandbox.yaml)

這份檔案顯示：

1. kind 是 `Sandbox`
2. namespace 是 `openshell`
3. label 包含 `openshell.ai/managed-by: openshell`
4. status 裡有 `serviceFQDN`

這證明實際流程是：

- OpenShell gateway 建立 `Sandbox`
- `agent-sandbox` controller 再把它 reconcile 成 Pod / Service / PVC

## 3. Supervisor 真的存在，而且不是概念名詞

### 證據 1: Pod command

- [proof-auto-pod.yaml](/Users/hwchiu/hwchiu/openqq/testing/raw/architecture-evidence/proof-auto-pod.yaml)

agent container 的 command 是：

```text
/opt/openshell/bin/openshell-sandbox
```

這代表 Pod 裡不是直接執行使用者程式，而是先跑 OpenShell supervisor。

### 證據 2: sandbox log

- [proof-auto-sandbox-log.txt](/Users/hwchiu/hwchiu/openqq/testing/raw/architecture-evidence/proof-auto-sandbox-log.txt)

這份 log 直接出現了 supervisor 在做的事情：

1. `Creating network namespace`
2. `Landlock filesystem sandbox available`
3. `Applying Landlock filesystem sandbox`
4. `HTTP:GET ALLOWED`
5. `HTTP:POST DENIED`

也就是說，supervisor 不是單純 wrapper，而是真正的本地 enforcement 點。

## 4. OpenShell sandbox 跟普通 Pod 的差異，在這個 cluster 上真的有被觀察到

### 證據 1: child process 身份不是 root

已實測：

```text
uid=998(sandbox) gid=998(sandbox)
```

### 證據 2: filesystem policy 有效

已實測：

```text
ls / -> Permission denied
touch /tmp/... -> 成功
touch /var/tmp/... -> Permission denied
```

### 證據 3: egress 預設拒絕

已實測：

```text
curl https://api.github.com/zen -> CONNECT tunnel failed, response 403
```

### 證據 4: binary 級別與 L7 級別控制有效

已實測：

1. `/usr/bin/curl` + `GET /zen` -> 允許
2. `python3` + `GET /zen` -> 拒絕
3. `/usr/bin/curl` + `POST /repos/.../issues` -> 拒絕

對應 raw evidence 在：

- [verify-1780439786](/Users/hwchiu/hwchiu/openqq/testing/raw/verify-1780439786)

## 5. Kubernetes service account token 預設沒有掛進 sandbox child process

已實測：

```text
K8S_SA_ABSENT
OPENSHELL_BOOTSTRAP_PRESENT
```

這代表：

1. 一般 Kubernetes API token 不是預設暴露給 sandbox child process
2. 但 OpenShell 仍然保留它自己的 bootstrap token 路徑，讓 supervisor 去完成和 gateway 的身份交換

## 6. 目前 k3s + containerd 的現實限制

在這個 cluster 上，OpenShell sandbox 最初其實會失敗，錯誤是：

```text
mount --make-shared /run/netns failed: Permission denied
```

這說明了兩件事：

1. OpenShell 的特殊性之一確實是自己的 netns / proxy enforcement
2. 但目前的 Kubernetes 權限模型還不足以原生滿足它

所以 repo 內增加了自動修正機制：

- [openshell-sandbox-patcher.yaml](/Users/hwchiu/hwchiu/openqq/k8s/openshell-sandbox-patcher.yaml)

而且這個 patcher 已實測成功：

1. 新建 `proof-auto-...` sandbox
2. 不手動 patch
3. sandbox 仍然自動變成 `Ready`

## 7. 結論

這份證據報告可以支持下面幾個明確結論：

1. OpenShell 確實有 Kubernetes driver
2. OpenShell 在 Kubernetes 上確實是透過 `agent-sandbox` 承載 sandbox workload
3. Supervisor 確實存在，而且是 runtime enforcement 的核心
4. OpenShell sandbox 確實不是普通 Pod
5. 目前 `k3s + containerd` 可以驗證 OpenShell 特性，但還需要 workaround 才能穩定運作
