# Terraform K3s + CRI-O Runbook

## 目的

把目前 Azure 上的 `k3s + containerd` 環境，切換成 `k3s + CRI-O`，並重跑相同的 OpenShell 驗證流程。

## 目前 repo 已完成的準備

1. Terraform 新增 `container_runtime`
2. Terraform 新增 `crio_version`
3. cloud-init 模板已支援在 Ubuntu 22.04 上安裝 CRI-O
4. K3s 啟動參數已支援 `--container-runtime-endpoint unix:///var/run/crio/crio.sock`
5. OpenShell runtime 驗證腳本已可重跑

## 設定方式

在 [terraform/terraform.tfvars](/Users/hwchiu/hwchiu/openqq/terraform/terraform.tfvars) 加上：

```hcl
container_runtime = "crio"
crio_version      = "v1.35"
```

## 執行順序

1. `terraform plan`
2. `terraform apply`
3. 重新抓 kubeconfig
4. 驗證 node runtime
5. 重新安裝 OpenShell stack
6. 重新跑 OpenShell 驗證腳本

## 驗證指令

### 1. 確認節點 runtime

```bash
kubectl --kubeconfig generated/kubeconfig get nodes -o wide
```

預期 `CONTAINER-RUNTIME` 欄位會從：

```text
containerd://...
```

變成：

```text
cri-o://...
```

### 2. 重新安裝 OpenShell stack

```bash
make openshell-install
```

### 3. 重新跑 OpenShell 驗證

```bash
make openshell-verify
```

## 要重新比較的項目

切到 CRI-O 後，至少要重跑並比對：

1. sandbox 是否仍需 `privileged` workaround
2. supervisor 的 netns 建立是否仍失敗
3. default deny egress 是否一致
4. filesystem policy 是否一致
5. binary allowlist / L7 policy 是否一致
6. static vs dynamic policy 行為是否一致

## 成功標準

1. 三個節點都 `Ready`
2. `kubectl get nodes -o wide` 顯示 `cri-o://`
3. OpenShell gateway 正常
4. 新建 sandbox 可 `Ready`
5. `scripts/verify-openshell-runtime.sh` 完整通過

## 官方參考

1. [K3s agent CLI](https://docs.k3s.io/cli/agent)
2. [K3s advanced options](https://docs.k3s.io/advanced)
3. [CRI-O packaging](https://github.com/cri-o/packaging)
