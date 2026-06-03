# OpenShell 架構介紹

這份文件把目前 repo 內已經驗證過的概念整併成一個完整介紹，目標是回答下面幾個問題：

1. `OpenShell` 是什麼
2. `OpenShell sandbox` 跟 `agent-sandbox` 的關係是什麼
3. `driver` 是什麼
4. `supervisor` 是什麼
5. 哪些是文件宣稱，哪些是我們已經在這個叢集上實測驗證的

## 一句話先講完

- `OpenShell` 是整個系統
- `OpenShell sandbox` 是被 OpenShell runtime 保護的執行環境
- `agent-sandbox` 是 Kubernetes SIG 提供的底層 `Sandbox` CRD/controller
- `driver` 是 OpenShell 把抽象 sandbox 語意翻譯成不同基礎設施操作的轉接層
- `supervisor` 是每個 sandbox 裡真正執行本地 enforcement 的元件

## 元件分層

### 1. CLI

CLI 是操作入口。

在這個 repo 的實際操作裡，我們用它做了：

1. 建立 sandbox
2. 連進 sandbox
3. 套用 policy
4. 讀取 logs

### 2. Gateway

Gateway 是 control plane。

它負責：

1. sandbox state
2. policy version
3. settings delivery
4. provider / credential mapping
5. relay coordination
6. compute driver orchestration

在目前 cluster 中，gateway 對應的是：

- namespace `openshell`
- pod `openshell-0`

### 3. Driver

Driver 是 OpenShell 和底層基礎設施之間的轉接層。

它的責任不是做 runtime enforcement，而是把 OpenShell 的抽象 sandbox 語意轉成平台動作。

在 Kubernetes 路徑上：

1. gateway 接到 `CreateSandbox`
2. Kubernetes driver 建立 `agents.x-k8s.io/v1alpha1` 的 `Sandbox`
3. 交給 `agent-sandbox` controller 去建立 Pod / Service / PVC

目前這個環境已經實際證明在使用的是 Kubernetes driver，證據在：

- [openshell-configmap.yaml](/Users/hwchiu/hwchiu/openqq/testing/raw/architecture-evidence/openshell-configmap.yaml)
- [openshell-driver-log.txt](/Users/hwchiu/hwchiu/openqq/testing/raw/architecture-evidence/openshell-driver-log.txt)

關鍵佐證包括：

1. config 中存在 `[openshell.drivers.kubernetes]`
2. gateway log 出現 `openshell_driver_kubernetes::driver`
3. log 內可見 `CreateSandbox`、`Listing sandboxes from Kubernetes` 等事件

### 4. agent-sandbox

`agent-sandbox` 不是 OpenShell 本體。

它是 Kubernetes SIG 的專案，提供：

1. `Sandbox` CRD
2. controller
3. stable service identity
4. singleton / PVC / lifecycle 這類 Kubernetes 承載能力

在這個 repo 的實際角色是：

1. 承接 OpenShell Kubernetes driver 建出的 `Sandbox` 物件
2. 將 `Sandbox` reconcile 成 Pod / Service / PVC

目前這個環境的實際證據：

- [agent-sandbox-controller-pod.yaml](/Users/hwchiu/hwchiu/openqq/testing/raw/architecture-evidence/agent-sandbox-controller-pod.yaml)
- [proof-auto-sandbox.yaml](/Users/hwchiu/hwchiu/openqq/testing/raw/architecture-evidence/proof-auto-sandbox.yaml)

### 5. OpenShell sandbox

`OpenShell sandbox` 在 Kubernetes 上表面看起來像一個 Pod，但語意上不是普通 Pod。

它的核心特徵是：

1. supervisor 先啟動
2. supervisor 再啟動 child process
3. process / filesystem / network / credential / inference 控制在本地生效
4. sandbox 和 gateway 維持長連線 session

### 6. Supervisor

Supervisor 是每個 sandbox 內最重要的 runtime enforcement 元件。

它的責任不是管理 Kubernetes 物件，而是在 sandbox 內：

1. 建立 network namespace
2. 準備 policy proxy
3. 載入 filesystem policy
4. 降權執行 child process
5. 處理 gateway 下發的動態設定
6. 發送 sandbox logs

在我們這個環境中的直接證據：

- sandbox pod 的 command 不是直接跑 agent，而是 `/opt/openshell/bin/openshell-sandbox`
- sandbox log 中可見 `Landlock filesystem sandbox`、`Creating network namespace`、`HTTP:GET ALLOWED`、`HTTP:POST DENIED`

對應證據：

- [proof-auto-pod.yaml](/Users/hwchiu/hwchiu/openqq/testing/raw/architecture-evidence/proof-auto-pod.yaml)
- [proof-auto-sandbox-log.txt](/Users/hwchiu/hwchiu/openqq/testing/raw/architecture-evidence/proof-auto-sandbox-log.txt)

## 這幾層是怎麼串起來的

目前這個 repo 的實際路徑是：

`openshell CLI -> gateway -> kubernetes driver -> agent-sandbox Sandbox CR -> sandbox Pod -> supervisor -> restricted child process`

所以：

- `driver` 解的是平台轉接
- `agent-sandbox` 解的是 Kubernetes 承載
- `supervisor` 解的是 sandbox 內部 enforcement

## 已經被實測證明的 OpenShell 特性

目前這個 repo 不只在講概念，而是已經實測出下面這些特性：

1. sandbox child process 以 `sandbox` 使用者執行
2. root filesystem 可見性受限，`ls /` 被拒絕
3. `/tmp` 可寫，但 `/var/tmp` 預設不可寫
4. 對外 egress 預設拒絕
5. 指定 binary 才能連指定 endpoint
6. 同一個 binary 對不同 HTTP method/path 有不同結果
7. network policy 可熱更新，不重建 Pod
8. filesystem policy 屬於靜態控制，不會因 live update 立即改變
9. sandbox 預設不自動掛載 Kubernetes service account token
10. 但會有 OpenShell bootstrap token 供 supervisor 向 gateway 換 sandbox JWT

## gVisor 路徑的新增結論

在 `k3s + containerd + RuntimeClass gvisor` 這條路徑上，我們又驗證到一個重要差異：

1. OpenShell 的 network policy、binary allowlist、L7 method/path 控制與 policy hot-reload 仍然成立
2. `agent-sandbox` 承載與 Kubernetes driver 路徑也仍然成立
3. 但 `filesystem_policy` 在目前這組合下沒有成立
4. 直接證據是 sandbox log 反覆出現 `Landlock Filesystem Sandbox Unavailable`
5. 對應行為是 `filesystem.txt` 出現 `VARTMP_OK`，而不是 runc 組的 `VARTMP_DENIED`

所以目前應該把 gVisor 視為：

- 增加 runtime 邊界
- 但不保證 OpenShell 所有 enforcement 都能原封不動保留下來

## 一個很重要的現實限制

目前這個 `k3s + containerd` 路徑下，OpenShell sandbox 並不是原生就能正常運作。

我們已實際遇到：

```text
Network namespace creation failed and proxy mode requires isolation
mount --make-shared /run/netns failed: Permission denied
```

所以目前 repo 裡另外加了一個 workaround：

- [openshell-sandbox-patcher.yaml](/Users/hwchiu/hwchiu/openqq/k8s/openshell-sandbox-patcher.yaml)

它會自動把 OpenShell 建出的 sandbox CR 補成 `privileged: true`，並在必要時刪掉舊 Pod 讓 controller 重建。

這不是最終架構答案，但它讓目前 `containerd` lab 可以穩定驗證 OpenShell 的 runtime 特性。

## 官方文件對照

這份介紹對照的官方資料包括：

1. [How OpenShell Works](https://docs.nvidia.com/openshell/about/how-it-works)
2. [Overview of NVIDIA OpenShell](https://docs.nvidia.com/openshell/latest/about/overview.html)
3. [Set Up OpenShell on Kubernetes](https://docs.nvidia.com/openshell/kubernetes/setup)
4. [Customize Sandbox Policies](https://docs.nvidia.com/openshell/latest/sandboxes/policies.html)
5. [First Sandbox Network Policy Tutorial](https://docs.nvidia.com/openshell/tutorials/first-network-policy)
6. [Security Best Practices](https://docs.nvidia.com/openshell/security/best-practices)
7. [Sandbox Compute Drivers](https://docs.nvidia.com/openshell/reference/sandbox-compute-drivers)

這次補看的兩份文件讓兩件事更清楚：

1. `server.enableUserNamespaces=true` 是 user namespace 防禦加成，不是用來移除 privileged bootstrap helpers
2. 如果目標是 VM 邊界，OpenShell 官方其實已有 `vm` compute driver，不必先假設 Kubernetes + Kata 一定是最自然的整合路徑

## 推薦閱讀順序

1. [docs/openshell-vs-sandbox.md](/Users/hwchiu/hwchiu/openqq/docs/openshell-vs-sandbox.md)
2. [docs/openshell-architecture.md](/Users/hwchiu/hwchiu/openqq/docs/openshell-architecture.md)
3. [testing/openshell-sandbox-validation-2026-06-03.md](/Users/hwchiu/hwchiu/openqq/testing/openshell-sandbox-validation-2026-06-03.md)
4. [testing/openshell-architecture-evidence-2026-06-03.md](/Users/hwchiu/hwchiu/openqq/testing/openshell-architecture-evidence-2026-06-03.md)
