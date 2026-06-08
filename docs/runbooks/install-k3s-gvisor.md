# Install Path: K3s + gVisor

這條路線只建立 `k3s + gVisor`，不安裝 OpenShell。

## 最短路徑

```bash
./scripts/install-k3s-gvisor.sh
```

## 它會做什麼

1. 套用 `terraform/stacks/k3s-gvisor`
2. 抓回 kubeconfig 到 `generated/stacks/k3s-gvisor/kubeconfig`
3. 等三個節點都 `Ready`
4. 驗證 `RuntimeClass/gvisor`

## 對應 Terraform Root

- `terraform/stacks/k3s-gvisor`

## 對應腳本

- `scripts/install-k3s-gvisor.sh`
- `scripts/fetch-kubeconfig-from-stack.sh`
- `scripts/verify-gvisor-runtime.sh`

## 輸出位置

- kubeconfig: `generated/stacks/k3s-gvisor/kubeconfig`
- Terraform state: `terraform/stacks/k3s-gvisor/terraform.tfstate`

## 清理

```bash
./scripts/destroy-comparison-matrix.sh
# 或單獨 destroy
source ./scripts/lib-stack.sh && terraform_destroy_stack k3s-gvisor
```
