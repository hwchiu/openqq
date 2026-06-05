# Azure File CSI Lab

本實驗的目標不是驗證 OpenShell CLI 本身，而是先回答一個更基本的問題：

1. Azure File CSI 能不能在這個 `k3s on Azure VM` 叢集上工作
2. CSI-backed PVC 能不能同時掛進普通 Pod 與 `Sandbox`
3. `Sandbox` 內看到的是否真的是同一個共享檔案系統

## 驗證路徑

1. 安裝官方 `azurefile-csi-driver`
2. 在 Azure 建立 storage account 與 file share
3. 用 Azure File CSI 建立靜態 `PV/PVC`
4. 把同一顆 `PVC` 掛進普通 Pod
5. 把同一顆 `PVC` 掛進 `agents.x-k8s.io/v1alpha1` `Sandbox`
6. 讓普通 Pod 寫檔，讓 `Sandbox` 讀取並追加內容，再回頭由 Pod 讀取確認

## 執行

```bash
./scripts/verify-azurefile-csi.sh
```

必要環境變數：

```bash
export RESOURCE_GROUP=rg-azure-k3s-lab-tf
export LOCATION=eastus
export KUBECONFIG_PATH=generated/kubeconfig
```

可選環境變數：

```bash
export STORAGE_ACCOUNT=stopenqqcustom
export FILE_SHARE=openshell-csi-share
export NAMESPACE=csi-lab
```

## Repo 內的靜態範本

- `k8s/azurefile-csi-static-template.yaml`
- `k8s/azurefile-csi-pod.yaml`
- `k8s/agent-sandbox-azurefile.yaml`

## 成功判準

以下三件事都成立才算通過：

1. `Pod` 與 `Sandbox` 都成功 `Ready`
2. 兩者都能在 `/mnt/azurefile` 看到已掛載的 Azure File share
3. `Pod` 寫入的內容可被 `Sandbox` 讀取與修改，且修改後可被 `Pod` 再次讀取
