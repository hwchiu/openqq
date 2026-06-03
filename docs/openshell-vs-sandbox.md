# OpenShell、OpenShell Sandbox、Agent Sandbox 差異說明

這三個詞很容易混在一起，但它們其實不是同一層的東西。

## 先講最短版

1. `OpenShell` 是整個產品 / 系統
2. `OpenShell sandbox` 是 OpenShell 管理下的一個受限制執行環境
3. `agent-sandbox` 是 Kubernetes SIG 提供的底層 CRD / controller，OpenShell 在 Kubernetes 上拿它來「承載」sandbox workload

所以關係不是:

- `OpenShell = sandbox`

而是:

- `OpenShell` 會在 Kubernetes 上利用 `agent-sandbox` 去建立 `OpenShell sandbox`

## 分層來看

### 1. OpenShell

`OpenShell` 是整個系統名稱。  
它至少包含三個核心元件:

1. CLI
2. Gateway
3. Supervisor

官方文件的核心描述是:

- CLI 是使用者入口
- Gateway 是 control plane
- Supervisor 在每個 sandbox 裡面，負責本地 enforcement

也就是說，當你說「OpenShell 很厲害」時，真正厲害的點通常不是單一 Pod，而是這整個協作模型。

### 2. OpenShell sandbox

`OpenShell sandbox` 是一個被 OpenShell 管理的執行環境。

在我們這個 Kubernetes 場景裡，它表面上看起來像一個 Pod，但實際上它不是普通 Pod 的語意。

它的特點是:

1. 有 supervisor 先啟動
2. agent process 不是直接裸跑，而是由 supervisor 啟動
3. supervisor 會套用 filesystem / process / network / credential / inference 等控制
4. sandbox 會跟 gateway 維持 session，接受動態設定更新

你可以把它理解成:

- 普通 Pod 是「有個 container 在跑」
- OpenShell sandbox 是「有個受 OpenShell runtime 保護與協調的 agent 執行空間」

### 3. agent-sandbox

`agent-sandbox` 不是 OpenShell 本體。  
它是 Kubernetes SIG 的專案，提供 `Sandbox` CRD 與 controller。

它負責的是比較底層、偏 Kubernetes 資源管理的事情，例如:

1. 建立對應 Pod
2. 建立對應 Service
3. 維持 stable identity
4. 維持 singleton / PVC / lifecycle

它本身不等於 OpenShell policy engine，也不等於 OpenShell gateway。

所以:

- `agent-sandbox` 解的是「Kubernetes 上怎麼表示與管理一個 sandbox workload」
- `OpenShell` 解的是「怎麼把 agent 關進可控 runtime，並以 policy、gateway、supervisor 去做安全治理」

## 在我們這個 repo 裡，三者的對應

### Kubernetes 上的物件

- `agent-sandbox` controller: 安裝在 `agent-sandbox-system`
- OpenShell gateway: 安裝在 `openshell` namespace，主要是 `openshell-0`
- OpenShell sandbox workload: 例如 `proof-demo`

### 實際關係

1. 我用 `openshell sandbox create` 建立 sandbox
2. OpenShell gateway 接到請求
3. Gateway 透過 Kubernetes driver 建立 `agents.x-k8s.io/v1alpha1` 的 `Sandbox`
4. `agent-sandbox` controller 看見這個 CRD，替它建立 Pod / Service / PVC
5. Pod 裡的 supervisor 啟動，向 gateway 拉 policy 與設定
6. supervisor 在本地對 child process 做 enforcement

所以執行路徑是:

`CLI -> Gateway -> Kubernetes driver -> agent-sandbox CRD/controller -> sandbox Pod -> supervisor -> agent child process`

## 為什麼前面容易混淆

因為在 Kubernetes 上你最後看到的東西常常是:

1. 一個 `Sandbox` CRD
2. 一個 Pod
3. 一個 Service

如果只看這些表面資源，很容易誤以為:

- sandbox 特性就是 CRD controller 給的

但這不對。

真正的 OpenShell 特性在我們這次實驗裡，主要來自 supervisor 與 gateway 之間的模型:

1. 預設 deny egress
2. binary 級別 allowlist
3. L7 method/path 控制
4. Landlock filesystem sandbox
5. static vs dynamic policy 分層
6. policy 熱更新而不重建 Pod

這些都不是 `agent-sandbox` 單獨提供的。

## 這次實驗證明了什麼

### agent-sandbox 提供的部分

這次能看到它提供的東西主要是:

1. 用 `Sandbox` CRD 來承載 workload
2. 幫 workload 建 Pod / Service / PVC
3. 提供 stable identity 與 lifecycle controller

### OpenShell 額外提供的部分

這次真正驗證到的 OpenShell 特性是:

1. child process 以 `sandbox` 使用者執行
2. root filesystem 可見性受限
3. `/tmp` 可寫但 `/var/tmp` 預設不可寫
4. 對外 egress 預設拒絕
5. 只有指定 binary 可以連特定 endpoint
6. 同一 binary 對不同 HTTP method/path 有不同結果
7. network policy 可熱更新
8. filesystem/process policy 屬於靜態控制，不會隨 live update 立即改變

## 一句話區分

如果要最簡單地記:

- `agent-sandbox` 是 Kubernetes 底層承載器
- `OpenShell sandbox` 是被 OpenShell runtime 保護的執行環境
- `OpenShell` 是整個 control plane + runtime enforcement 系統

## 對後續工作的意義

這個區分很重要，因為它決定你下一步要修什麼。

如果問題是:

- Pod 沒起來
- PVC 沒掛
- Service 沒建立

通常先看 `agent-sandbox` 與 Kubernetes controller 行為。

如果問題是:

- 為什麼某個 binary 被拒絕
- 為什麼 `GET` 可以但 `POST` 不行
- 為什麼 `/var/tmp` 還是不能寫
- 為什麼 policy 更新了但某些效果沒變

通常要看 OpenShell gateway / policy / supervisor。

## 補一個常見誤解: 換成 gVisor 不等於 OpenShell 全面升級

這次在 `k3s + gVisor` 上的驗證很值得特別寫下來：

1. `OpenShell` 的 L7 與 binary 級治理仍然有效
2. `agent-sandbox` 仍然只是在承載 workload
3. `gVisor` 提供的是更底層的 syscall / kernel 邊界
4. 但 `OpenShell filesystem_policy` 在目前這個組合下退化，沒有像 runc 組那樣透過 Landlock 生效

所以這三者不是互相取代，而是三個不同層次：

- `agent-sandbox`：Kubernetes 承載
- `OpenShell`：agent 行為治理
- `gVisor`：runtime / kernel 邊界

## 再補一個常見混淆: Kubernetes 路徑不等於 VM 路徑

OpenShell 的 compute driver 不只有 Kubernetes。

如果你看到我們在 repo 裡測：

- `RuntimeClass: gvisor`
- `RuntimeClass: kata`

這代表的是：

- OpenShell 走的是 **Kubernetes driver**
- Kubernetes 再把 sandbox pod 交給不同 runtime 執行

但 OpenShell 官方另外還有：

- `vm` compute driver

所以：

- `OpenShell + agent-sandbox + RuntimeClass/kata` 是「Kubernetes 路徑中的 VM-ish runtime 實驗」
- `OpenShell vm driver` 才是「OpenShell 官方原生 VM sandbox 路徑」

這個差別很重要，因為它直接影響後續該優先優化哪一條路。
