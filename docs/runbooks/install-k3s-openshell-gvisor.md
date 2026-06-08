# Install Path: K3s + OpenShell + gVisor

這條路線驗證 OpenShell 在 `runsc` runtime 上保留與退化哪些能力。

## 最短路徑

```bash
./scripts/install-k3s-openshell-gvisor.sh
```

## 它會做什麼

1. 套用 `terraform/stacks/k3s-openshell-gvisor`
2. 抓回 kubeconfig 到 `generated/stacks/k3s-openshell-gvisor/kubeconfig`
3. 等三個節點都 `Ready`
4. 驗證 `RuntimeClass/gvisor`
5. 安裝 OpenShell，但跳過預設 patcher
6. 套用 `gvisor` 專用 patcher
7. 執行 OpenShell runtime 驗證

## 對應 Terraform Root

- `terraform/stacks/k3s-openshell-gvisor`

## 對應腳本

- `scripts/install-k3s-openshell-gvisor.sh`
- `scripts/install-openshell-stack.sh`
- `scripts/install-openshell-sandbox-patcher-gvisor.sh`
- `scripts/verify-gvisor-runtime.sh`
- `scripts/verify-openshell-runtime.sh`

## 已知結果

- `network / L7 / hot-reload` 可驗證
- `filesystem_policy` 在 gVisor 路徑退化

## 清理

```bash
./scripts/destroy-comparison-matrix.sh
# 或單獨 destroy
source ./scripts/lib-stack.sh && terraform_destroy_stack k3s-openshell-gvisor
```
