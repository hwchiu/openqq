# OpenShell FUSE 驗證報告

日期: 2026-06-05
環境: Azure `k3s + containerd + runc + OpenShell`

## 結論

這輪實驗的結論不是單純的「可以」或「不可以」，而是更精準的三段式結果：

1. `runc` 基線下，普通 privileged Pod 可以成功使用 `sshfs` 掛載遠端目錄
2. OpenShell sandbox 若使用預設 base image，因為沒有 `sshfs/fusermount3`，且不允許把 process user 改成 `root`，所以不能靠 sandbox 內臨時安裝完成測試
3. 即使改成自訂 `amd64` image，讓 sandbox 內具備 `/dev/fuse`、`sshfs`、`fusermount3`、`sshpass`，OpenShell sandbox 仍然無法連到本實驗中的 SSH endpoint，因此最終 `sshfs` mount 仍未成立

所以目前可以誠實地說：

- OpenShell sandbox 內已具備 FUSE 裝置與 helper binaries
- 但在目前這個 `k3s + OpenShell Kubernetes driver` 路徑下，**以 `sshfs` 方式把遠端空間掛成檔案系統，尚未成功**
- 主要阻塞點已經收斂到 **sandbox 網路路徑對 SSH/TCP endpoint 的可達性模型**，而不是 FUSE 本身

## 這次驗證到的事實

### 1. runc 基線本身沒有 FUSE 問題

基線報告已證明：

- 普通 privileged Pod 可使用 `sshfs`
- 可掛載遠端目錄到 `/mnt/remote`
- 可讀取 `hello.txt`
- `mount` 顯示 `type fuse.sshfs`
- 可正常 `fusermount3 -u`

參考:
- [testing/fuse-runc-baseline-2026-06-05.md](/Users/hwchiu/hwchiu/openqq/testing/fuse-runc-baseline-2026-06-05.md)

### 2. OpenShell 不允許把 live sandbox 的 process policy 改成 root

這次直接驗證到：

- live sandbox 上 `process policy cannot be changed`
- 建立 sandbox 時若 policy 指定 `run_as_user: root` / `run_as_group: root`，Gateway 會直接拒絕，訊息是：

```text
policy contains unsafe content:
run_as_user must be 'sandbox', got 'root'; run_as_group must be 'sandbox', got 'root'
```

這代表 OpenShell 很明確地把 sandbox 執行身份固定在 `sandbox` 使用者，而不是讓使用者任意升成 root。

這是安全模型的一部分，不是 incidental bug。

### 3. 自訂 image 後，sandbox 內的 FUSE 先決條件已滿足

我做了一個自訂 image：
- [sandbox-images/fuse-sshfs/Dockerfile](/Users/hwchiu/hwchiu/openqq/sandbox-images/fuse-sshfs/Dockerfile)

這個 image 預裝：
- `sshfs`
- `fuse3`
- `fusermount3`
- `sshpass`
- `openssh-client`

建立 sandbox 後，`prereq.txt` 顯示：

```text
uid=998(sandbox) gid=998(sandbox)
crw-rw-rw- 1 root root 10, 229 ... /dev/fuse
/usr/bin/sshfs
/usr/bin/fusermount3
/usr/bin/sshpass
```

所以這時候問題已經不是：
- 缺 `/dev/fuse`
- 缺 binary
- 缺 `fuse.conf`

### 4. 失敗點在網路，不在 FUSE binary

#### 4.1 對叢集內部 Service DNS

OpenShell sandbox 內：

```text
nc: getaddrinfo for host "sshfs-server.fuse-lab.svc.cluster.local" port 2222: Temporary failure in name resolution
```

代表 sandbox netns 內對 `svc.cluster.local` 沒有直接可用的 DNS 解析路徑。

#### 4.2 對 ClusterIP / PodIP

把 DNS 移除後，直接打：
- `10.43.180.66:2222`（Service IP）
- `10.42.2.3:2222`（Pod IP）

普通 Pod 對照結果：

```text
Connection to 10.43.180.66 2222 port [tcp/*] succeeded!
SVC_OK
Connection to 10.42.2.3 2222 port [tcp/*] succeeded!
POD_OK
SSH_OK
```

OpenShell sandbox 結果：

```text
nc: connect to 10.43.180.66 port 2222 (tcp) failed: Connection refused
nc: connect to 10.42.2.3 port 2222 (tcp) failed: Connection refused
```

#### 4.3 對 NodePort / 外部 IP

我把 SSH server 額外暴露成 `NodePort 32222`，再用節點公網 IP 測：
- `20.169.142.67:32222`

普通 Pod 對照結果：

```text
Connection to 20.169.142.67 32222 port [tcp/*] succeeded!
NODEPORT_OK
SSH_OK
```

OpenShell sandbox 結果：

```text
nc: connect to 20.169.142.67 port 32222 (tcp) failed: Connection refused
```

這非常重要。

它代表：
- 問題不是只有 `svc.cluster.local` DNS
- 問題也不是只有 k8s Service CIDR
- 即使換成對 sandbox 來說更像「外部遠端」的 NodePort 路徑，這個 SSH/TCP endpoint 仍然不通

## 對 OpenShell 的真正解讀

目前這輪最合理的技術判讀是：

1. OpenShell sandbox 可以承載 FUSE 裝置與 helper binary
2. 但它目前的預設網路模型，是為受控的 HTTP/REST / inference / policy-driven egress 設計
3. 對 `sshfs` 這種需要直接打 SSH/TCP endpoint 的 remote filesystem workflow，不是現成可用路徑

換句話說：

- **FUSE 本身不是第一阻塞點**
- **OpenShell sandbox 的網路可達性模型才是第一阻塞點**

## 我認為最值得的下一步

如果你的真正目標是「在 sandbox 內掛遠端空間當檔案系統」，目前有三條路：

1. 改測 `rclone mount` + WebDAV / S3 / HTTPS backend
   - 這最符合 OpenShell 現有的 REST/L7 policy 脈絡
   - 比 `sshfs` 更有機會成功

2. 深挖 OpenShell 是否存在可描述 generic TCP / SSH endpoint 的正式 policy 模型
   - 如果沒有，`sshfs` 路徑就不會是自然路徑

3. 若一定要 `sshfs`
   - 需要更低層地釐清 sandbox netns 到該 endpoint 的封包路徑
   - 這已經不是單純的應用配置問題，而是 OpenShell runtime/driver 行為問題

## 原始證據

### runc 基線
- [testing/raw/fuse-runc-baseline-2026-06-05/sshfs-baseline.log](/Users/hwchiu/hwchiu/openqq/testing/raw/fuse-runc-baseline-2026-06-05/sshfs-baseline.log)

### OpenShell root policy 驗證
- [testing/raw/fuse-rootcheck-1780666464/id-before.txt](/Users/hwchiu/hwchiu/openqq/testing/raw/fuse-rootcheck-1780666464/id-before.txt)
- [testing/raw/fuse-rootcheck-1780666464/policy-set.txt](/Users/hwchiu/hwchiu/openqq/testing/raw/fuse-rootcheck-1780666464/policy-set.txt)
- [testing/raw/fuse-rootcheck-1780666464/id-after.txt](/Users/hwchiu/hwchiu/openqq/testing/raw/fuse-rootcheck-1780666464/id-after.txt)

### OpenShell FUSE image / sandbox 驗證
- [testing/raw/fuse-sshfs-proof-1780667803/create.txt](/Users/hwchiu/hwchiu/openqq/testing/raw/fuse-sshfs-proof-1780667803/create.txt)
- [testing/raw/fuse-sshfs-proof-1780667803/prereq.txt](/Users/hwchiu/hwchiu/openqq/testing/raw/fuse-sshfs-proof-1780667803/prereq.txt)
- [testing/raw/fuse-sshfs-proof-1780667803/connectivity.txt](/Users/hwchiu/hwchiu/openqq/testing/raw/fuse-sshfs-proof-1780667803/connectivity.txt)
- [testing/raw/fuse-sshfs-proof-1780667803/mount.txt](/Users/hwchiu/hwchiu/openqq/testing/raw/fuse-sshfs-proof-1780667803/mount.txt)
- [testing/raw/fuse-sshfs-proof-1780667803/sandbox-logs.txt](/Users/hwchiu/hwchiu/openqq/testing/raw/fuse-sshfs-proof-1780667803/sandbox-logs.txt)
