# Azure File CSI 掛載驗證

日期：2026-06-06  
環境：Azure `k3s + containerd + runc`  
目的：驗證 `CSI-backed PVC` 是否能成功掛進普通 Pod 與 `agents.x-k8s.io/v1alpha1` `Sandbox`

## 結論

驗證通過。

這次不是把 PVC 只掛進普通 Pod，而是做了更強的共享驗證：

1. 在 Azure 上建立 `Storage Account + File Share`
2. 安裝官方 `azurefile-csi-driver`
3. 用 Azure File CSI 建立靜態 `PV/PVC`
4. 把同一顆 `PVC` 同時掛進：
   - 普通 Pod `azurefile-pod-001841`
   - `Sandbox` `azurefile-sandbox-001841`
5. 讓普通 Pod 先寫入 `proof.txt`
6. 讓 `Sandbox` 讀到同一個檔案，再追加內容
7. 回頭讓普通 Pod 再讀一次，確認已看到 `Sandbox` 回寫的內容

這證明了兩件事：

1. Azure File CSI 在這個自建 `k3s on Azure VM` 叢集上可正常工作
2. `Sandbox` 可以把 CSI-backed PVC 當成一般 filesystem 使用，而不是只能靠 FUSE 或本機 `local-path`

## 實際掛載結果

普通 Pod 與 `Sandbox` 內都看到相同的 Azure File mount：

```text
//stopenqq06001115.file.core.windows.net/openshell-csi-share on /mnt/azurefile type cifs
```

這代表不是假裝成 emptyDir，也不是 node local path，而是 Azure File share 經由 CSI 真正掛入容器檔案系統。

## 共享讀寫證據

### 1. 普通 Pod 先寫入

```text
from-pod
```

來源：
- `testing/raw/azurefile-csi-1780676321/pod-proof.txt`

### 2. Sandbox 讀到同一檔案並追加

```text
from-pod
from-pod
from-sandbox
```

來源：
- `testing/raw/azurefile-csi-1780676321/sandbox-proof.txt`

判讀：
- 第一行 `from-pod` 代表 `Sandbox` 已經讀到 Pod 寫入的原始內容
- 最後新增 `from-sandbox` 代表 `Sandbox` 成功回寫同一份 share

### 3. 普通 Pod 再讀一次

```text
from-pod
from-sandbox
```

來源：
- `testing/raw/azurefile-csi-1780676321/pod-final.txt`

判讀：
- Pod 最後看到 `Sandbox` 的新增內容
- 這證明兩邊不是各自掛到不同目錄，而是確實共用同一顆 Azure File-backed PVC

## 本次建立的 Kubernetes 物件

Namespace:
- `csi-lab`

PV/PVC:
- `pv-azurefile-001841`
- `pvc-azurefile-001841`

Workloads:
- `Pod/azurefile-pod-001841`
- `Sandbox/azurefile-sandbox-001841`

## raw 證據

- `testing/raw/azurefile-csi-1780676321/pv.yaml`
- `testing/raw/azurefile-csi-1780676321/pvc.yaml`
- `testing/raw/azurefile-csi-1780676321/pod.yaml`
- `testing/raw/azurefile-csi-1780676321/sandbox.yaml`
- `testing/raw/azurefile-csi-1780676321/pod-proof.txt`
- `testing/raw/azurefile-csi-1780676321/sandbox-proof.txt`
- `testing/raw/azurefile-csi-1780676321/pod-final.txt`
- `testing/raw/azurefile-csi-1780676321/csi-driver-pods.txt`

## 這代表什麼

這次驗證回答的是：

- `PVC mount into sandbox filesystem`：可以
- `CSI-backed remote storage`：可以
- `不需要在 sandbox 內跑 sshfs`：對，至少這個 Azure File 路徑不需要

但這次還沒有直接驗證：

- OpenShell CLI 建立的 `workspace` 是否能直接切到 Azure File storage class
- OpenShell sandbox 是否能在不 patch CR 的情況下額外再掛第二顆 PVC

所以目前最精準的結論是：

> 在這個 lab 上，`agent-sandbox` / `Sandbox` CR 已可成功使用 Azure File CSI-backed PVC。  
> 這條路比 `sshfs in sandbox` 更像正式 Kubernetes 儲存方案。

## 下一步

最自然的下一步有兩條：

1. 把 OpenShell `workspace` 這顆 PVC 改成 Azure File-backed storage class
2. 驗證 OpenShell 自動產生的 `Sandbox` 是否能透過 patch 或 driver 設定多掛一顆額外 PVC
