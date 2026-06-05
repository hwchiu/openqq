# runc FUSE 基線驗證報告

日期: 2026-06-05
環境: Azure `k3s + containerd + runc`
目的: 先證明 FUSE remote mount 在普通 privileged Pod 可行，再把 OpenShell sandbox 視為第二階段問題。

## 結論

這輪基線驗證通過。

我們已證明在目前 Azure lab 中：

1. 三個節點都存在 `/dev/fuse`
2. 普通 `privileged` Pod 可以安裝 `fuse3` / `sshfs`
3. Pod 可以透過 `sshfs` 把叢集內的遠端 SSH endpoint 掛載到 `/mnt/remote`
4. 掛載後可列出遠端目錄、讀取檔案、看到 `type fuse.sshfs` mount entry
5. `fusermount3 -u` 可正常卸載

因此，如果下一階段 OpenShell sandbox 內失敗，阻塞點就不在 Azure、k3s、containerd 或 FUSE 基本路徑，而在：

1. OpenShell sandbox 是否能使用 `/dev/fuse`
2. sandbox image 是否含 `sshfs` / `fusermount3` / `fuse3`
3. sandbox 的 `privileged` / `SYS_ADMIN` 是否足夠
4. OpenShell 的 filesystem policy 與 network policy 是否阻擋掛載流程

## 測試設計

這一輪故意不從 OpenShell 開始。

遠端端點:
- `k8s/fuse-ssh-server.yaml`
- 在 namespace `fuse-lab` 內建立 `sshfs-server` deployment + service
- Pod 內提供 `/data/export`

客戶端:
- `k8s/fuse-sshfs-baseline.yaml`
- 使用 `ubuntu:24.04`
- 開 `privileged: true`
- 額外加 `SYS_ADMIN`
- 動態安裝 `sshfs fuse3 openssh-client sshpass`

## 重要結果

### 節點前置條件

三台機器都觀察到：

```text
DEV_FUSE_PRESENT
crw-rw-rw- 1 root root 10, 229 ... /dev/fuse
```

`lsmod` 沒看到 `fuse` 不構成失敗，因為實際 mount 已成功。

### 成功掛載證據

來自 `sshfs-baseline.log` 的關鍵輸出：

```text
+ sshfs fuseuser@sshfs-server.fuse-lab.svc.cluster.local:/data/export /mnt/remote -p 2222 -o password_stdin,allow_other,default_permissions,reconnect
+ ls -la /mnt/remote
-rw-r--r-- 1 ubuntu ubuntu   12 ... hello.txt
+ cat /mnt/remote/hello.txt
server-file
+ mount
+ grep /mnt/remote
fuseuser@sshfs-server.fuse-lab.svc.cluster.local:/data/export on /mnt/remote type fuse.sshfs (...)
+ fusermount3 -u /mnt/remote
```

這已足夠證明：
- remote SSH space 已被掛成 filesystem
- 檔案讀取成功
- mount type 為 `fuse.sshfs`
- unmount 成功

## 對 OpenShell sandbox 測試的意義

這份報告只證明 FUSE 在 `runc` 基線可行，不代表 OpenShell sandbox 內一定可行。

但它把問題空間大幅縮小了。

接下來若要驗證 OpenShell sandbox，合理順序是：

1. 先做 `sshfs` 版 sandbox PoC
2. 若網路政策不好描述，再改做 `rclone mount` + HTTPS backend
3. 分開驗證：
   - `/dev/fuse` 是否存在
   - `sshfs` / `fusermount3` 是否可執行
   - mount syscall 是否被允許
   - 遠端連線是否被 OpenShell policy 放行

## 原始證據

- [nodes.txt](/Users/hwchiu/hwchiu/openqq/testing/raw/fuse-runc-baseline-2026-06-05/nodes.txt)
- [fuse-lab-resources.txt](/Users/hwchiu/hwchiu/openqq/testing/raw/fuse-runc-baseline-2026-06-05/fuse-lab-resources.txt)
- [sshfs-baseline.log](/Users/hwchiu/hwchiu/openqq/testing/raw/fuse-runc-baseline-2026-06-05/sshfs-baseline.log)
- [sshfs-baseline.describe.txt](/Users/hwchiu/hwchiu/openqq/testing/raw/fuse-runc-baseline-2026-06-05/sshfs-baseline.describe.txt)
- [all-pods.txt](/Users/hwchiu/hwchiu/openqq/testing/raw/fuse-runc-baseline-2026-06-05/all-pods.txt)
