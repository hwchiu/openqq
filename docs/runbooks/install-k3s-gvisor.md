# Install Path: K3s + gVisor

這條路線只回答一件事：

- 建立一套 `k3s + containerd + RuntimeClass gvisor` 的獨立叢集
- 不安裝 OpenShell
- 只驗證 gVisor runtime 本身是否可用

## 適用場景

- 你只想驗證 `runsc` 是否能在 Azure VM 上穩定跑起來
- 你想先驗證 runtime 邊界，不想混入 OpenShell 變數
- 你要做後續 `gVisor + OpenShell` 前的乾淨基準

## 先決條件

- 已完成 Azure 登入與 subscription 選定
- 已準備 `terraform/terraform.tfvars`
- `generated/kubeconfig` 可由控制平面抓回

## 安裝流程

1. 佈署基礎 K3s 叢集

```bash
make tf-init
make tf-plan
make tf-apply
./scripts/fetch-kubeconfig.sh
kubectl --kubeconfig generated/kubeconfig get nodes -o wide
```

2. 安裝 gVisor

```bash
make gvisor-install
```

這一步會：

- 在 worker 節點安裝 `runsc`
- 修改 K3s containerd 模板
- 重啟 `k3s-agent`
- 套用 `RuntimeClass/gvisor`

3. 驗證 gVisor runtime

```bash
make gvisor-verify
```

## 驗證成功條件

- `kubectl get runtimeclass gvisor` 存在
- `runtimeClassName: gvisor` 的驗證 Pod 成功完成
- Pod 內 `uname -a` 顯示 `gvisor`

## Repo 內關鍵檔案

- `scripts/install-gvisor.sh`
- `scripts/verify-gvisor-runtime.sh`
- `k8s/gvisor-runtimeclass.yaml`
- `docs/lab-gvisor.html`

## 這條路線不包含

- OpenShell
- agent-sandbox
- KubeArmor

## 清理

```bash
make tf-destroy
```
