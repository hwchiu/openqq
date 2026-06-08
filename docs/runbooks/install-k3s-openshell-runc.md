# Install Path: K3s + OpenShell + runc

這是目前最完整、最穩的 OpenShell 主線。

## 最短路徑

```bash
./scripts/install-k3s-openshell-runc.sh
```

## 它會做什麼

1. 套用 `terraform/stacks/k3s-openshell-runc`
2. 抓回 kubeconfig 到 `generated/stacks/k3s-openshell-runc/kubeconfig`
3. 等三個節點都 `Ready`
4. 安裝 `agent-sandbox`
5. 安裝 OpenShell Helm chart
6. 套用預設 `runc` patcher
7. 執行 OpenShell runtime 驗證

## 對應 Terraform Root

- `terraform/stacks/k3s-openshell-runc`

## 對應腳本

- `scripts/install-k3s-openshell-runc.sh`
- `scripts/install-openshell-stack.sh`
- `scripts/install-openshell-sandbox-patcher.sh`
- `scripts/verify-openshell-runtime.sh`

## 輸出位置

- kubeconfig: `generated/stacks/k3s-openshell-runc/kubeconfig`
- raw runtime evidence: `testing/raw/verify-*`

## 清理

```bash
./scripts/destroy-comparison-matrix.sh
# 或單獨 destroy
source ./scripts/lib-stack.sh && terraform_destroy_stack k3s-openshell-runc
```
