# OpenQQ Azure Kata Containers 驗證文件

這個 repository 目前只記錄一條已驗證路徑：`Azure 上的 K3s 1.34 + CRI-O 1.34 + Kata Containers`。

文件範圍刻意維持精簡，只回答三件事：

1. 這個環境怎麼安裝
2. 這個環境怎麼驗證
3. 目前在 Kata 環境中實際執行過哪些測試

## 建議閱讀順序

1. [總覽](docs/index.html)
2. [安裝](docs/install.html)
3. [驗證](docs/verify.html)
4. [已執行測試](docs/tests.html)
5. [原始證據](docs/evidence.html)

## 最新驗證環境

- 初次 runtime verify：`2026-06-25`
- 補強 node-side live inspect：`2026-06-28`
- Kata + Istio sidecar smoke：`2026-06-28`
- Kata + NetworkPolicy smoke：`2026-06-28`
- Kata + Azure Files NFS CSI static mount：`2026-06-28`
- Kata + Azure Files NFS CSI dynamic provisioning：`2026-06-28 (執行失敗)`
- Kata + Azure Files SMB CSI dynamic StorageClass：`2026-06-29`
- 雲端平台：Azure
- Resource group：`rg-k3s-kata-134`
- Cluster 名稱：`k3s-kata-134`
- 節點數：`3`
- VM 規格：`Standard_D4s_v3`
- 作業系統：`Ubuntu 22.04.5 LTS`
- Host kernel：`6.8.0-1059-azure`
- Kubernetes：`v1.34.1+k3s1`
- Container runtime：`cri-o://1.34.9`
- Kata 驗證結果：`RuntimeClass kata` 建立成功，probe pod 輸出 `kata-probe-ok`
- Service mesh 驗證結果：`Istio control plane ready (istiod-1.30.2)`，Kata-backed echo / curl pod 回應 `kata-mesh-ok`
- NetworkPolicy 驗證結果：baseline 時兩個 Kata client 都可連線，套用 ingress policy 後只有標記過的 client 可連，未標記 client 會被阻擋
- Filesystem / CSI 驗證結果：官方可重跑路徑改為 `Azure Files SMB dynamic StorageClass`，`StorageClass -> PVC -> 兩個 Kata pod` 可成功 provision、掛載與跨節點讀寫；另外保留 `Azure Files NFS` 的補充結果，其中 static CSI 掛載可通，但 dynamic provisioning 仍會失敗

## 安裝方式

先準備共用 Azure 變數檔 `terraform/stacks/common.auto.tfvars`：

```hcl
subscription_id = "00000000-0000-0000-0000-000000000000"
tenant_id       = "00000000-0000-0000-0000-000000000000"
admin_username  = "azureuser"
ssh_public_key  = "ssh-ed25519 AAAA..."
```

然後執行 one-shot installer：

```bash
cp terraform/stacks/common.auto.tfvars.example terraform/stacks/common.auto.tfvars
cp terraform/stacks/k3s-kata-134/stack.auto.tfvars.example terraform/stacks/k3s-kata-134/stack.auto.tfvars
bash scripts/install-k3s-kata-134.sh
```

這個 wrapper script 會依序做以下事情：

1. 對 `terraform/stacks/k3s-kata-134` 執行 `terraform apply`
2. 等待 3 個節點都變成 `Ready`
3. 執行 `scripts/check-kata-prereqs.sh`
4. 執行 `scripts/install-kata.sh`
5. 執行 `scripts/verify-kata-runtime.sh`

目前驗證時使用的預設值如下：

- `K3s v1.34.1+k3s1`
- `CRI-O v1.34`
- `Standard_D4s_v3`
- `Ubuntu 22.04 LTS`
- `scripts/install-kata.sh` 內的 `KATA_VERSION=3.31.0`

## 驗證方式

如果要重跑驗證，可以執行：

```bash
KUBECONFIG_PATH=generated/stacks/k3s-kata-134/kubeconfig \
TF_DIR=terraform/stacks/k3s-kata-134 \
bash scripts/check-kata-prereqs.sh

KUBECONFIG_PATH=generated/stacks/k3s-kata-134/kubeconfig \
bash scripts/verify-kata-runtime.sh

KUBECONFIG_PATH=generated/stacks/k3s-kata-134/kubeconfig \
TF_DIR=terraform/stacks/k3s-kata-134 \
bash scripts/verify-azurefile-csi.sh

KUBECONFIG_PATH=generated/stacks/k3s-kata-134/kubeconfig \
TF_DIR=terraform/stacks/k3s-kata-134 \
AZUREFILE_CSI_PROFILE=nfs \
bash scripts/verify-azurefile-csi.sh
```

預期結果：

- 3 個節點都顯示 `Ready`
- 每個節點都存在 `/dev/kvm`
- `kubectl get runtimeclass kata` 成功
- verify pod 進入 `Succeeded`
- pod logs 內含 guest kernel 資訊與 `kata-probe-ok`
- 如果重跑預設 CSI 腳本，JSON 會輸出 `status=pass`，且 `dynamic.pvcStatus=Bound`
- 如果改跑 `AZUREFILE_CSI_PROFILE=nfs`，則會看到 static 路徑成功、dynamic 路徑失敗

## 更強的 Kata 證明鏈

如果要更明確證明該 pod 不是單純「有設 `runtimeClassName`」，而是真的跑在 Kata VM sandbox 內，repo 也保存了 `2026-06-28` 的 node-side live inspect：

- pod spec 明確要求 `runtimeClassName: kata`
- pod 內看到的 guest kernel 是 `6.18.28`
- Azure worker node 的 host kernel 是 `6.8.0-1059-azure`
- worker node 上的 `crictl inspectp` 記錄了 `io.kubernetes.cri-o.RuntimeHandler = "kata"`
- worker node 的 process list 出現同一個 sandbox ID 對應的 `containerd-shim-kata-v2`、`qemu-system-x86_64` 與 `virtiofsd`

同一天也另外保存了 `Kata + Istio` 的 live 證據，用來證明 sidecar 疊加之後仍然是 Kata sandbox：

- `istiod` control plane 已成功 Ready
- server / client pod 的 spec 都保留 `runtimeClassName: kata`
- server / client pod 的 `crictl inspectp` 都記錄 `io.kubernetes.cri-o.RuntimeHandler = "kata"`
- server / client pod 都帶有 `sidecar.istio.io/status`
- node-side process list 同時出現兩個 Istio workload sandbox 對應的 `containerd-shim-kata-v2`、`qemu-system-x86_64` 與 `virtiofsd`

同一天也另外保存了 `Kata + NetworkPolicy` 的 live 證據，用來證明標準 Kubernetes ingress policy 在 Kata pod 上有實際的 allow / block 效果：

- baseline 階段 `allowed` 與 `blocked` 兩個 Kata client 都可以連到 server service，回應都是 `np-ok`
- 套用 `allow-only-labeled` ingress `NetworkPolicy` 之後，帶有 `access=allowed` label 的 Kata client 仍可連線
- 未帶 label 的 Kata client 會收到 `curl: (7) Failed to connect ...`
- server / allowed / blocked 三個 pod 的 spec 都保留 `runtimeClassName: kata`
- server / allowed / blocked 三個 sandbox 的 `crictl inspectp` 都記錄 `io.kubernetes.cri-o.RuntimeHandler = "kata"`

同一天也另外保存了 `Kata + Azure Files SMB CSI` 的 live 證據，作為目前官方可重跑的 `StorageClass -> PVC -> pod` 驗證路徑：

- `Azure File CSI driver 1.35.4` 的 controller / node plugin 都成功 Ready
- 動態 `StorageClass` 會在既有 Azure storage account 內自動 provision share，PVC 會進入 `Bound`
- 兩個 `runtimeClassName: kata` pod 分別落在 `worker-1` 與 `worker-2`，都成功掛上同一個 dynamic volume
- Kata guest 內看到的掛載型別是 `virtiofs`，代表 host 端掛好的 volume 是再透過 Kata shared-fs 暴露進 VM
- worker node host 端看到的同一個 volume 則是 `//st...file.core.windows.net/... type cifs`，可直接證明底層後端真的是 Azure Files SMB
- writer / reader 兩個 Kata pod 可以跨節點共享檔案；在這次 `actimeo=30` 的 mount option 下，writer 端約 35 秒後可重新看到 reader append 的第二行

另外也保存了 `Kata + Azure Files NFS CSI` 的補充證據，用來回答「Kata pod 能不能透過 CSI 吃到 NFS 類型 storage」這個問題：

- `Azure File CSI driver 1.35.4` 的 controller / node plugin 都成功 Ready
- 兩個 `runtimeClassName: kata` pod 分別落在 `worker-1` 與 `worker-2`，都成功掛上同一個 Azure Files NFS share
- Kata guest 內看到的掛載型別是 `virtiofs`，代表 host 端掛好的 volume 是再透過 Kata shared-fs 暴露進 VM
- worker node host 端看到的同一個 volume 則是 `st...file.core.windows.net:/... type nfs4`，可直接證明底層後端真的是 Azure Files NFS
- writer / reader 兩個 Kata pod 可以跨節點共享檔案；在這次 `actimeo=30` 的 mount option 下，reader append 的第二行大約要 35 秒後才會在 writer 端再次讀到
- 如果改走 dynamic `StorageClass -> PVC -> pod` provisioning，`csi-azurefile-controller` 會在 `CreateVolume` 時 panic，PVC 會停留在 `Pending`

## Kata 環境中已執行的測試

| 測試項目 | 狀態 | 證據 |
| --- | --- | --- |
| 3 節點 Azure cluster bootstrap | 通過 | [nodes-wide.txt](records/raw/2026-06-25/k3s-kata-134-runtime-verify/nodes-wide.txt) |
| Kubernetes 與 cluster-info 擷取 | 通過 | [versions.txt](records/raw/2026-06-25/k3s-kata-134-runtime-verify/versions.txt) |
| 全節點 `/dev/kvm` prerequisite | 通過 | [prereqs.txt](records/raw/2026-06-25/k3s-kata-134-runtime-verify/prereqs.txt) |
| 全節點 CRI-O Kata drop-ins 已寫入 | 通過 | [crio-kata-dropins.txt](records/raw/2026-06-25/k3s-kata-134-runtime-verify/crio-kata-dropins.txt) |
| `RuntimeClass kata` 物件存在 | 通過 | [runtimeclass-kata.yaml](records/raw/2026-06-25/k3s-kata-134-runtime-verify/runtimeclass-kata.yaml) |
| Kata probe pod 完成執行 | 通過 | [kata-evidence-pod.yaml](records/raw/2026-06-25/k3s-kata-134-runtime-verify/kata-evidence-pod.yaml) |
| Kata probe log 含 `kata-probe-ok` | 通過 | [kata-evidence-logs.txt](records/raw/2026-06-25/k3s-kata-134-runtime-verify/kata-evidence-logs.txt) |
| Live proof pod 指定 `runtimeClassName: kata` | 通過 | [pod.yaml](records/raw/2026-06-28/kata-proof-3-live-inspect/pod.yaml) |
| `crictl inspectp` 顯示 `RuntimeHandler=kata` | 通過 | [crictl-inspectp.json](records/raw/2026-06-28/kata-proof-3-live-inspect/crictl-inspectp.json) |
| Worker node 啟動 `containerd-shim-kata-v2`、`qemu-system-x86_64`、`virtiofsd` | 通過 | [kata-processes.txt](records/raw/2026-06-28/kata-proof-3-live-inspect/kata-processes.txt) |
| `crio` journal 記錄 Kata proof pod 的 sandbox 與 container 啟動 | 通過 | [crio-journal.txt](records/raw/2026-06-28/kata-proof-3-live-inspect/crio-journal.txt) |
| Istio control plane Ready | 通過 | [istio-control-plane.json](records/raw/2026-06-28/k3s-kata-134-istio-sidecar/istio-control-plane.json) |
| Kata + Istio sidecar smoke | 通過 | [istio-kata-sidecar.json](records/raw/2026-06-28/k3s-kata-134-istio-sidecar/istio-kata-sidecar.json) |
| Kata + Istio server / client pod 保留 `runtimeClassName: kata` | 通過 | [server-pod.yaml](records/raw/2026-06-28/k3s-kata-134-istio-sidecar/server-pod.yaml), [client-pod.yaml](records/raw/2026-06-28/k3s-kata-134-istio-sidecar/client-pod.yaml) |
| Kata + Istio server / client sandbox 顯示 `RuntimeHandler=kata` | 通過 | [server-crictl-inspectp.json](records/raw/2026-06-28/k3s-kata-134-istio-sidecar/server-crictl-inspectp.json), [client-crictl-inspectp.json](records/raw/2026-06-28/k3s-kata-134-istio-sidecar/client-crictl-inspectp.json) |
| Kata + Istio node-side shim / qemu / virtiofsd process chain | 通過 | [kata-processes.txt](records/raw/2026-06-28/k3s-kata-134-istio-sidecar/kata-processes.txt) |
| Kata + NetworkPolicy ingress smoke | 通過 | [networkpolicy-kata-ingress.json](records/raw/2026-06-28/k3s-kata-134-networkpolicy/networkpolicy-kata-ingress.json) |
| Kata + NetworkPolicy rule 定義 | 通過 | [networkpolicy.yaml](records/raw/2026-06-28/k3s-kata-134-networkpolicy/networkpolicy.yaml) |
| Kata + NetworkPolicy server / client pod 保留 `runtimeClassName: kata` | 通過 | [server-pod.yaml](records/raw/2026-06-28/k3s-kata-134-networkpolicy/server-pod.yaml), [allowed-pod.yaml](records/raw/2026-06-28/k3s-kata-134-networkpolicy/allowed-pod.yaml), [blocked-pod.yaml](records/raw/2026-06-28/k3s-kata-134-networkpolicy/blocked-pod.yaml) |
| Kata + NetworkPolicy server / client sandbox 顯示 `RuntimeHandler=kata` | 通過 | [server-crictl-inspectp.json](records/raw/2026-06-28/k3s-kata-134-networkpolicy/server-crictl-inspectp.json), [allowed-crictl-inspectp.json](records/raw/2026-06-28/k3s-kata-134-networkpolicy/allowed-crictl-inspectp.json), [blocked-crictl-inspectp.json](records/raw/2026-06-28/k3s-kata-134-networkpolicy/blocked-crictl-inspectp.json) |
| Azure File CSI driver controller / node plugin Ready | 通過 | [csi-driver-pods-final.txt](records/raw/2026-06-29/k3s-kata-134-filesystem-csi-smb/csi-driver-pods-final.txt) |
| Azure Files SMB dynamic StorageClass 掛載到兩個 Kata pod | 通過 | [kata-azurefile-csi-smb.json](records/raw/2026-06-29/k3s-kata-134-filesystem-csi-smb/kata-azurefile-csi-smb.json), [pods-wide.txt](records/raw/2026-06-29/k3s-kata-134-filesystem-csi-smb/pods-wide.txt) |
| Kata guest 看到 `virtiofs`，worker host 看到底層 `cifs` | 通過 | [writer-exec.txt](records/raw/2026-06-29/k3s-kata-134-filesystem-csi-smb/writer-exec.txt), [worker-1-cifs-mounts.txt](records/raw/2026-06-29/k3s-kata-134-filesystem-csi-smb/worker-1-cifs-mounts.txt) |
| Azure Files SMB 動態 volume 跨節點共享檔案 | 通過 | [reader-exec.txt](records/raw/2026-06-29/k3s-kata-134-filesystem-csi-smb/reader-exec.txt), [final-proof-after-35s.txt](records/raw/2026-06-29/k3s-kata-134-filesystem-csi-smb/final-proof-after-35s.txt) |
| Azure Files NFS static CSI 掛載到兩個 Kata pod | 通過 | [kata-azurefile-csi-nfs.json](records/raw/2026-06-28/k3s-kata-134-filesystem-csi-nfs/kata-azurefile-csi-nfs.json), [pods-wide.txt](records/raw/2026-06-28/k3s-kata-134-filesystem-csi-nfs/pods-wide.txt) |
| Kata guest 看到 `virtiofs`，worker host 看到底層 `nfs4` | 通過 | [writer-exec.txt](records/raw/2026-06-28/k3s-kata-134-filesystem-csi-nfs/writer-exec.txt), [worker-1-nfs-mounts.txt](records/raw/2026-06-28/k3s-kata-134-filesystem-csi-nfs/worker-1-nfs-mounts.txt) |
| Azure Files NFS 跨節點共享檔案 | 通過 | [reader-exec.txt](records/raw/2026-06-28/k3s-kata-134-filesystem-csi-nfs/reader-exec.txt), [final-proof-after-35s.txt](records/raw/2026-06-28/k3s-kata-134-filesystem-csi-nfs/final-proof-after-35s.txt) |
| Azure Files NFS dynamic CSI provisioning | 失敗 | [kata-azurefile-csi-nfs.json](records/raw/2026-06-28/k3s-kata-134-filesystem-csi-nfs/kata-azurefile-csi-nfs.json), [dynamic-controller-panic.txt](records/raw/2026-06-28/k3s-kata-134-filesystem-csi-nfs/dynamic-controller-panic.txt), [dynamic-pvc.describe.txt](records/raw/2026-06-28/k3s-kata-134-filesystem-csi-nfs/dynamic-pvc.describe.txt) |
| Filesystem guardrail / protected path policy | 尚未測試 | 目前只驗證了 filesystem mount capability，還沒驗證 workspace / protected path allow / block |
| Privilege surface scenarios | 尚未測試 | 此環境未執行 |
| Agentic AI scenarios | 尚未測試 | 此環境未執行 |

## 原始證據

目前保存的 Kata 驗證證據在：

- `records/raw/2026-06-25/k3s-kata-134-runtime-verify/`
- `records/raw/2026-06-28/kata-proof-3-live-inspect/`
- `records/raw/2026-06-28/k3s-kata-134-istio-sidecar/`
- `records/raw/2026-06-28/k3s-kata-134-networkpolicy/`
- `records/raw/2026-06-29/k3s-kata-134-filesystem-csi-smb/`
- `records/raw/2026-06-28/k3s-kata-134-filesystem-csi-nfs/`

GitHub Pages 現在只聚焦在 Kata 的安裝、驗證與已執行測試，不再包含跨 solution 的比較頁面。
