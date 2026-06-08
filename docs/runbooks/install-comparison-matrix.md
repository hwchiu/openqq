# Install Path: Four-Way Comparison Matrix

這條路線不是新的 runtime，而是把四套環境一起建起來。

## 目標

同時維持四個彼此獨立的 Azure lab：

1. `k3s-gvisor`
2. `k3s-openshell-runc`
3. `k3s-openshell-gvisor`
4. `k3s-kubearmor-runc`

每套環境都有獨立的：

- Terraform state
- Azure resource group
- VNet/subnet CIDR
- kubeconfig
- post-install path

## 最短路徑

```bash
./scripts/install-comparison-matrix.sh
```

這支腳本目前用安全的 serial 流程逐套建立，但對使用者來說仍然是一個入口命令。

## 共享輸入來源

優先順序如下：

1. `terraform/stacks/common.auto.tfvars`
2. 環境變數
3. `terraform/terraform.tfvars` 中的共用欄位

## 產物位置

- `generated/stacks/k3s-gvisor/kubeconfig`
- `generated/stacks/k3s-openshell-runc/kubeconfig`
- `generated/stacks/k3s-openshell-gvisor/kubeconfig`
- `generated/stacks/k3s-kubearmor-runc/kubeconfig`

## 清理整組環境

```bash
./scripts/destroy-comparison-matrix.sh
```
